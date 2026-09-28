-- Native progress dispatch and transitions, using the real texture renderers.
-- Recording frames deliberately do not emulate native layout or secret taint.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local secret = newproxy(true)
for _, operation in ipairs({"__add", "__sub", "__mul", "__div", "__lt", "__le", "__eq", "__unm", "__concat", "__tostring"}) do
  getmetatable(secret)[operation] = function() error("Computed with secret progress") end
end
local function issecretvalue(value)
  return type(value) == "userdata" and getmetatable(value) == getmetatable(secret)
end
local function hasanysecretvalues(...)
  for i = 1, select("#", ...) do
    if issecretvalue(select(i, ...)) then return true end
  end
  return false
end
local function copy(source)
  local result = {}
  for key, value in pairs(source) do
    result[key] = type(value) == "table" and copy(value) or value
  end
  return result
end
local function noop() end
local function close(first, second)
  return math.abs(first - second) < 0.000001
end

local frameMethods, statusBars = {}, {}
local frameObjects = 0
local function frame(kind, _, parent)
  frameObjects = frameObjects + 1
  local object = setmetatable({kind = kind, parent = parent, calls = {}, points = {}, masks = {}, scripts = {}, shown = true},
    {__index = frameMethods})
  if kind == "StatusBar" then statusBars[#statusBars + 1] = object end
  return object
end
local function record(self, name, ...)
  self.calls[name] = self.calls[name] or {}
  local args = {...}
  self.calls[name][#self.calls[name] + 1] = args
  return args
end
local function last(object, name)
  local calls = object.calls[name]
  return calls and calls[#calls]
end
for _, name in ipairs({
  "SetMovable", "SetResizable", "SetResizeBounds", "SetDrawLayer", "SetSnapToPixelGrid",
  "SetTexelSnappingBias", "SetVertexOffset", "SetTexCoord", "SetVertexColor", "SetDesaturated",
  "SetRotation", "SetAlpha", "SetFrameLevel", "SetFrameStrata", "SetClipsChildren", "SetClipsToBounds",
  "SetRenderMode", "SetRadialDirection", "SetRadialStartAngle", "SetRadialEndAngle",
  "SetClockwise", "SetReverseFill", "SetOrientation", "SetRotatesTexture", "SetColorTexture", "SetColorFill",
  "SetStatusBarColor", "SetTexture", "SetAtlas", "SetScale", "SetFillStyle", "SetTimerDuration",
  "ClearRadialProgressBar", "SetRadialProgressBarStartOffset", "SetRadialProgressBarEndOffset",
  "SetRadialProgressBarReverse", "SetRadialProgressBarFeather", "SetRadialProgressBarPercent",
  "SetToTargetValue",
}) do
  frameMethods[name] = function(self, ...) record(self, name, ...) end
end
function frameMethods:CreateTexture() return frame("Texture", nil, self) end
function frameMethods:CreateMaskTexture() return frame("MaskTexture", nil, self) end
function frameMethods:Show() self.shown = true end
function frameMethods:Hide() self.shown = false end
function frameMethods:IsShown() return self.shown end
function frameMethods:SetShown(shown) self.shown = shown end
function frameMethods:SetScript(script, fn) self.scripts[script] = fn end
function frameMethods:GetFrameLevel() return 1 end
function frameMethods:GetParent() return self.parent end
function frameMethods:SetWidth(width) self.frameWidth = width end
function frameMethods:SetHeight(height) self.frameHeight = height end
function frameMethods:SetSize(width, height) self.frameWidth, self.frameHeight = width, height end
function frameMethods:GetWidth() return self.frameWidth or (self.parent and self.parent:GetWidth()) or 200 end
function frameMethods:GetHeight() return self.frameHeight or (self.parent and self.parent:GetHeight()) or 200 end
function frameMethods:GetSize() return self:GetWidth(), self:GetHeight() end
function frameMethods:ClearAllPoints()
  record(self, "ClearAllPoints")
  self.points, self.allPoints = {}, nil
end
function frameMethods:SetPoint(...)
  record(self, "SetPoint", ...)
  if self.allPoints then
    self.points = {{"TOPLEFT", self.allPoints, "TOPLEFT"}, {"BOTTOMRIGHT", self.allPoints, "BOTTOMRIGHT"}}
    self.allPoints = nil
  end
  local point = {...}
  for index, previous in ipairs(self.points) do
    if previous[1] == point[1] then
      self.points[index] = point
      return
    end
  end
  self.points[#self.points + 1] = point
end
function frameMethods:SetAllPoints(target)
  record(self, "SetAllPoints", target)
  self.allPoints = target or self.parent
end
function frameMethods:AddMaskTexture(mask) self.masks[mask] = true end
function frameMethods:RemoveMaskTexture(mask) self.masks[mask] = nil end
function frameMethods:SetBlendMode(mode) self.blendMode = mode end
function frameMethods:GetBlendMode() return self.blendMode end
function frameMethods:SetStatusBarTexture(texture)
  record(self, "SetStatusBarTexture", texture)
  if type(texture) == "table" then
    self.statusTexture = texture
  else
    self.statusTexture = self.statusTexture or self:CreateTexture()
    self.statusTexture:SetTexture(texture)
  end
end
function frameMethods:GetStatusBarTexture() return self.statusTexture end
function frameMethods:SetMinMaxValues(minimum, maximum)
  self.minimum, self.maximum = minimum, maximum
  record(self, "SetMinMaxValues", minimum, maximum)
end
function frameMethods:GetMinMaxValues() return self.minimum, self.maximum end
function frameMethods:SetValue(value, interpolation)
  self.value = value
  self.timer = nil
  record(self, "SetValue", value, interpolation)
end
function frameMethods:SetTimerDuration(duration, interpolation, direction)
  self.timer = duration
  record(self, "SetTimerDuration", duration, interpolation, direction)
end
function frameMethods:GetValue() return self.value end
function frameMethods:SetVertexOffset(vertex, x, y)
  self.vertices = self.vertices or {}
  self.vertices[vertex] = {x, y}
  record(self, "SetVertexOffset", vertex, x, y)
end
function frameMethods:SetRadialProgressBarPercent(value)
  self.radialPercent = value
  record(self, "SetRadialProgressBarPercent", value)
end
function frameMethods:ClearRadialProgressBar()
  self.radialPercent = nil
  record(self, "ClearRadialProgressBar")
end

-- Include simple state setters in dispatch counts used by the hot-path checks.
for _, name in ipairs({"Show", "Hide", "SetShown", "SetBlendMode", "SetWidth", "SetHeight", "SetSize"}) do
  local method = frameMethods[name]
  frameMethods[name] = function(self, ...)
    record(self, name, ...)
    return method(self, ...)
  end
end

-- Resolve only public numeric rectangles for the geometry checks below. This
-- verifies the anchor math; it cannot prove WoW's secret native layout behavior.
local anchorFractions = {
  TOPLEFT = {0, 0}, TOP = {0.5, 0}, TOPRIGHT = {1, 0},
  LEFT = {0, 0.5}, CENTER = {0.5, 0.5}, RIGHT = {1, 0.5},
  BOTTOMLEFT = {0, 1}, BOTTOM = {0.5, 1}, BOTTOMRIGHT = {1, 1},
}
local function rectangle(object)
  if object.allPoints then return rectangle(object.allPoints) end
  if object.parent and object.parent.statusTexture == object then
    local bar = object.parent
    local left, top, width, height = rectangle(bar)
    local progress = math.max(0, math.min(1, (bar.value - bar.minimum) / (bar.maximum - bar.minimum)))
    local horizontal = last(bar, "SetOrientation")[1] == "HORIZONTAL"
    local reverse = last(bar, "SetReverseFill")[1]
    if horizontal then
      if reverse then left = left + width * (1 - progress) end
      width = width * progress
    else
      if not reverse then top = top + height * (1 - progress) end
      height = height * progress
    end
    return left, top, width, height
  end
  local width, height = object.frameWidth or 200, object.frameHeight or 200
  local xPoints, yPoints = {}, {}
  for _, point in ipairs(object.points) do
    local own, target = anchorFractions[point[1]], anchorFractions[point[3]]
    local left, top, targetWidth, targetHeight = rectangle(point[2])
    xPoints[#xPoints + 1] = {own[1], left + target[1] * targetWidth + (point[4] or 0)}
    yPoints[#yPoints + 1] = {own[2], top + target[2] * targetHeight - (point[5] or 0)}
  end
  local function axis(points, size)
    if #points == 0 then return 0, size end
    for i = 2, #points do
      if points[i][1] ~= points[1][1] then
        size = (points[i][2] - points[1][2]) / (points[i][1] - points[1][1])
        break
      end
    end
    return points[1][2] - points[1][1] * size, size
  end
  local left, top
  left, width = axis(xPoints, width)
  top, height = axis(yPoints, height)
  return left, top, width, height
end
local corners = {{"UL", 0, 0}, {"LL", 0, 1}, {"UR", 1, 0}, {"LR", 1, 1}}
local function maskPolygon(mask)
  local left, top, width, height = rectangle(mask)
  local uv = last(mask, "SetTexCoord")
  local result = {}
  for vertex, corner in ipairs(corners) do
    local s, t = corner[2], corner[3]
    if #uv == 8 then
      local u, v = s - uv[1], t - uv[2]
      local a, b, c, d = uv[5] - uv[1], uv[3] - uv[1], uv[6] - uv[2], uv[4] - uv[2]
      local determinant = a * d - b * c
      s, t = (u * d - b * v) / determinant, (a * v - c * u) / determinant
    end
    local offset = mask.vertices and mask.vertices[vertex] or {0, 0}
    result[vertex] = {left + s * width + offset[1], top + t * height - offset[2]}
  end
  return result
end

local E = {
  StatusBarRenderMode = {Linear = 0, Radial = 1},
  StatusBarTimerDirection = {ElapsedTime = 0, RemainingTime = 1},
  StatusBarInterpolation = {Immediate = 0, ExponentialEaseOut = 1},
  StatusBarFillStyle = {Standard = 0, StandardNoRangeFill = 1},
  StatusBarRadialDirection = {Clockwise = 0, CounterClockwise = 1},
}
local registration, now
local warningCalls = {}
now = 100
local Private = {
  frames = {},
  StartProfileSystem = noop,
  StopProfileSystem = noop,
  AuraWarnings = {UpdateWarning = function(uid, key, severity, message)
    warningCalls[#warningCalls + 1] = {uid = uid, key = key, severity = severity, message = message}
  end},
  regionPrototype = {
    AddAlphaToDefault = noop,
    AddProgressSourceToDefault = noop,
    AddProperties = noop,
    modify = noop,
    modifyFinish = noop,
    create = function(region)
      region.subRegionEvents = {
        subscribers = {}, calls = {},
        AddSubscriber = function(self, event, owner)
          record(self, "AddSubscriber", event, owner)
          self.subscribers[event] = owner
        end,
        RemoveSubscriber = function(self, event, owner)
          record(self, "RemoveSubscriber", event, owner)
          if self.subscribers[event] == owner then self.subscribers[event] = nil end
        end,
        Notify = noop,
      }
    end,
  },
  SetTextureOrAtlas = function(texture, ...) texture:SetTexture(...) end,
  RegisterRegionType = function(name, create, modify, default)
    assert(name == "progresstexture")
    registration = {create = create, modify = modify, default = default}
  end,
}
local env = setmetatable({
  CreateFrame = frame,
  M33kAuras = {
    IsLibsOK = function() return true end,
    IsDurationObject = function(value) return type(value) == "table" and value.durationObject == true end,
    L = setmetatable({}, {__index = function(_, key) return key end}),
  },
  Enum = E,
  UPPER_LEFT_VERTEX = 1, LOWER_LEFT_VERTEX = 2, UPPER_RIGHT_VERTEX = 3, LOWER_RIGHT_VERTEX = 4,
  GetScreenWidth = function() return 1920 end,
  GetScreenHeight = function() return 1080 end,
  GetTime = function() return now end,
  issecretvalue = issecretvalue,
  hasanysecretvalues = hasanysecretvalues,
  CopyTable = copy,
  Mixin = function(target, source) for name, method in pairs(source) do target[name] = method end end,
  hooksecurefunc = function(target, name, callback)
    local original = target[name]
    target[name] = function(...)
      original(...)
      callback(...)
    end
  end,
  FrameDeltaLerp = function(current, target, amount) return current + (target - current) * amount end,
  Clamp = function(value, minimum, maximum) return math.max(minimum, math.min(maximum, value)) end,
  floor = math.floor, min = math.min, max = math.max,
  cos = function(value) return math.cos(math.rad(value)) end,
  sin = function(value) return math.sin(math.rad(value)) end,
  tan = function(value) return math.tan(math.rad(value)) end,
  CreateVector2D = function(x, y) return {x = x, y = y} end,
}, {__index = _G})
for _, path in ipairs({
  "BaseRegions/TextureCoords.lua", "BaseRegions/LinearProgressTexture.lua",
  "BaseRegions/CircularProgressTexture.lua", "RegionTypes/SmoothStatusBarMixin.lua",
  "RegionTypes/ProgressTexture.lua",
}) do
  setfenv(assert(loadfile(T.repoRoot .. "/M33kAuras/" .. path)), env)("M33kAuras", Private)
end
local function newRegion(options)
  local data = copy(registration.default)
  for key, value in pairs(options or {}) do data[key] = value end
  local region = registration.create(frame("Frame"))
  registration.modify(region.parent, region, data)
  region.minProgress, region.maxProgress = 0, 100
  region.progressType, region.value, region.total = "static", 25, 100
  return region, data
end
local function makeSecret(region)
  region.value, region.total = newproxy(secret), newproxy(secret)
  region:UpdateValue()
end
local function assertForwarded(bar, region, label)
  local bounds, value = last(bar, "SetMinMaxValues"), last(bar, "SetValue")
  T.expect(bounds and rawequal(bounds[1], region.minProgress) and rawequal(bounds[2], region.maxProgress),
    label .. " forwards adjusted bounds")
  T.expect(value and rawequal(value[1], region.value), label .. " forwards secret value without inspection")
end
local function nativeCalls(region)
  local result = {}
  local objects = {
    region.secretBar, region.secretAuxBar, region.secretBar:GetStatusBarTexture(),
    region.secretAuxBar:GetStatusBarTexture(), region.secretFillFrame, region.secretAuxFillFrame,
    region.secretTextureFrame, region.secretTexture, region.secretMask,
  }
  local seen = {}
  for _, object in ipairs(objects) do
    for name, calls in pairs(not seen[object] and object.calls or {}) do
      result[name] = (result[name] or 0) + #calls
    end
    seen[object] = true
  end
  return result
end
local function configurationCalls(region)
  local count = 0
  for name, calls in pairs(nativeCalls(region)) do
    if name ~= "SetMinMaxValues" and name ~= "SetValue" and name ~= "SetTimerDuration"
        and name ~= "SetRadialProgressBarPercent" then
      count = count + calls
    end
  end
  return count
end
local function subscriptionCalls(region)
  local calls = region.subRegionEvents.calls
  return #(calls.AddSubscriber or {}) + #(calls.RemoveSubscriber or {})
end
local function canonicalUV(texture)
  local uv = last(texture, "SetTexCoord")
  local expected = #uv == 4 and {0, 1, 0, 1} or {0, 0, 0, 1, 1, 0, 1, 1}
  if #uv ~= #expected then return false end
  for index, value in ipairs(expected) do if uv[index] ~= value then return false end end
  return true
end
local function artworkQuad(region)
  local width, height = region.width * region.scalex, region.height * region.scaley
  local result = {}
  for index, corner in ipairs(corners) do
    local offset = region.secretTexture.vertices[index]
    result[index] = {corner[2] + offset[1] / width, corner[3] - offset[2] / height}
  end
  return result
end
local function quadPoint(quad, u, v)
  return quad[1][1] + (quad[3][1] - quad[1][1]) * u + (quad[2][1] - quad[1][1]) * v,
         quad[1][2] + (quad[3][2] - quad[1][2]) * u + (quad[2][2] - quad[1][2]) * v
end
local function artworkMatchesOrdinary(region, ordinary)
  if not canonicalUV(region.secretTexture) then return false end
  local quad = artworkQuad(region)
  local a, b = quad[3][1] - quad[1][1], quad[2][1] - quad[1][1]
  local c, d = quad[3][2] - quad[1][2], quad[2][2] - quad[1][2]
  local determinant = a * d - b * c
  for _, point in ipairs({{0, 0}, {.2, .7}, {.5, .5}, {.9, .1}, {1, 1}}) do
    local x, y = point[1] - quad[1][1], point[2] - quad[1][2]
    local nativeU, nativeV = (x * d - b * y) / determinant, (a * y - c * x) / determinant
    local expectedU = ordinary[1] + (ordinary[5] - ordinary[1]) * point[1] + (ordinary[3] - ordinary[1]) * point[2]
    local expectedV = ordinary[2] + (ordinary[6] - ordinary[2]) * point[1] + (ordinary[4] - ordinary[2]) * point[2]
    if not close(nativeU, expectedU) or not close(nativeV, expectedV) then return false end
  end
  return true
end

T.section("Ordinary texture progress is preserved")
for _, orientation in ipairs({"HORIZONTAL", "HORIZONTAL_INVERSE", "VERTICAL", "VERTICAL_INVERSE", "CLOCKWISE", "ANTICLOCKWISE"}) do
  local region = newRegion({orientation = orientation})
  region:UpdateValue()
  T.expect(close(region.progress, 0.25) and not region.secretProgress, orientation .. " retains ordinary progress")
  region:SetInverse(true)
  T.expect(close(region.progress, 0.75), orientation .. " retains ordinary inversion")
end

T.section("Native linear values, orientations, and inverse changes")
local inverseMaskAnchors = {
  HORIZONTAL = {"TOPLEFT", "BOTTOMLEFT"}, HORIZONTAL_INVERSE = {"TOPRIGHT", "BOTTOMRIGHT"},
  VERTICAL = {"BOTTOMLEFT", "BOTTOMRIGHT"}, VERTICAL_INVERSE = {"TOPLEFT", "TOPRIGHT"},
}
for _, orientation in ipairs({"HORIZONTAL", "HORIZONTAL_INVERSE", "VERTICAL", "VERTICAL_INVERSE"}) do
  local region = newRegion({orientation = orientation, smoothProgress = true})
  region.minProgress, region.maxProgress = 50, 100
  makeSecret(region)
  assertForwarded(region.secretBar, region, orientation)
  T.expect(last(region.secretBar, "SetOrientation")[1] == (orientation:find("HORIZONTAL") and "HORIZONTAL" or "VERTICAL"),
    orientation .. " chooses matching native axis")
  local reversed = orientation:find("INVERSE") ~= nil
  T.expect(last(region.secretBar, "SetReverseFill")[1] == reversed, orientation .. " preserves fill origin")
  T.expect(last(region.secretBar, "SetValue")[2] == E.StatusBarInterpolation.ExponentialEaseOut,
    orientation .. " smooths with native interpolation")
  region:SetInverse(true)
  T.expect(last(region.secretBar, "SetReverseFill")[1] == not reversed, orientation .. " complements native fill")
  local points, expected = region.secretFillFrame.points, inverseMaskAnchors[orientation]
  T.expect(#points == 2 and points[1][1] == "TOPLEFT" and points[2][1] == "BOTTOMRIGHT"
      and points[1][3] == expected[1] and points[2][3] == expected[2],
    orientation .. " anchors opposite mask corners to the complementary area")
  region:SetInverse(false)
  T.expect(last(region.secretBar, "SetReverseFill")[1] == reversed, orientation .. " restores native fill after a second inverse toggle")
  T.expect(region.secretFillFrame.allPoints == region.secretBar:GetStatusBarTexture(),
    orientation .. " restores the direct native texture mask")
  T.expect(not region.foreground.visible and region.secretTexture:IsShown(),
    orientation .. " replaces ordinary geometry with the native foreground")
  T.expect(not region.FrameTick, orientation .. " needs no Lua progress tick")
end

do
  local region = newRegion({compress = true})
  makeSecret(region)
  T.expect(region.secretTextureFrame.allPoints == region.secretFillFrame and region.secretTexture.allPoints == region.secretTextureFrame,
    "compressed native texture follows the native fill geometry")
  region.value, region.total = 25, 100
  region:UpdateValue()
  T.expect(region.foreground.visible and close(region.progress, 0.25), "compressed texture returns to ordinary rendering")
end

T.section("Secret bounds and duration objects")
do
  local region = newRegion()
  region.minProgress, region.maxProgress = newproxy(secret), newproxy(secret)
  makeSecret(region)
  assertForwarded(region.secretBar, region, "secret bounds")
  for _, orientation in ipairs({"VERTICAL", "CLOCKWISE", "ANTICLOCKWISE"}) do
    region:SetOrientation(orientation)
    for _, triggerInverse in ipairs({false, true}) do
      for _, displayInverse in ipairs({false, true}) do
        region.inverse = triggerInverse
        region:SetInverse(displayInverse)
        region.durationObject = {durationObject = true}
        region:UpdateDuration()
        local duration = last(region.secretBar, "SetTimerDuration")
        T.expect(duration and duration[1] == region.durationObject,
          orientation .. " passes duration objects directly to the native timer")
        local remaining = triggerInverse == displayInverse
        T.expect(duration and (duration[3] or E.StatusBarTimerDirection.ElapsedTime)
            == (remaining and E.StatusBarTimerDirection.RemainingTime or E.StatusBarTimerDirection.ElapsedTime),
          orientation .. " combines trigger and display inverse for timer direction")
        T.expect((region.FrameTick ~= nil) == region.circular,
          orientation .. " duration uses the circular geometry ticker only when needed")
      end
    end
  end
end

T.section("Circular progress forwards native fractions without secret arithmetic")
for _, orientation in ipairs({"CLOCKWISE", "ANTICLOCKWISE"}) do
  local region = newRegion({orientation = orientation, startAngle = 90, endAngle = 270, smoothProgress = true})
  region.minProgress, region.maxProgress = 50, 100
  makeSecret(region)
  local source = region.secretBar
  assertForwarded(source, region, orientation)
  T.expect(source:IsShown() and region.secretBarMode == "circular" and not region.foregroundSpinner.visible,
    orientation .. " renders secret progress with circular native geometry")
  T.expect(last(source, "SetRenderMode")[1] == E.StatusBarRenderMode.Linear
      and source:GetWidth() == 65536 and source:GetHeight() == 1,
    orientation .. " uses the validated integer-width linear source")
  T.expect(last(region.secretFillFrame, "SetScale")[1] == 65536
      and region.secretFillFrame.allPoints == source:GetStatusBarTexture(),
    orientation .. " normalizes native width into a fraction independently of arc length")
  T.expect(last(source, "SetValue")[2] == E.StatusBarInterpolation.ExponentialEaseOut,
    orientation .. " interpolates the source before forwarding its fraction")
  T.expect(region.FrameTick and region.subRegionEvents.subscribers.FrameTick == region,
    orientation .. " subscribes the circular geometry bridge")
  local sourceFraction = newproxy(secret)
  region.secretFillFrame:SetWidth(sourceFraction)
  local configuration = configurationCalls(region)
  region:FrameTick()
  T.expect(rawequal(last(region.secretTexture, "SetRadialProgressBarPercent")[1], sourceFraction),
    orientation .. " passes the hostile secret fraction directly to the radial texture")
  T.expect(configurationCalls(region) == configuration,
    orientation .. " tick changes progress without rebuilding public artwork or geometry")
  region:SetInverse(true)
  assertForwarded(source, region, orientation .. " inverted source")
  T.expect(region.secretFillFrame.points[1][2] == source
      and region.secretFillFrame.points[2][2] == source:GetStatusBarTexture(),
    orientation .. " inverts the source through complementary anchors")
  region:SetInverse(false)
  T.expect(region.FrameTick and region.secretFillFrame.allPoints == source:GetStatusBarTexture(),
    orientation .. " restores direct readout while retaining its circular ticker")
  region.endAngle = region.startAngle + 360
  region:SetOrientation(region.orientation)
  T.expect(last(region.secretFillFrame, "SetScale")[1] == 65536
      and last(region.secretTexture, "SetRadialProgressBarEndOffset")[1] == 0,
    orientation .. " restores a full native sweep without changing fraction units")
  region:SetOrientation("VERTICAL")
  T.expect(not region.FrameTick and not region.subRegionEvents.subscribers.FrameTick
      and last(region.secretFillFrame, "SetScale")[1] == 1,
    orientation .. " releases circular ticking and restores ordinary linear readout units")
  T.expect(region.secretTexture.radialPercent == nil and last(region.secretTexture, "ClearRadialProgressBar"),
    orientation .. " clears radial clipping on the displayed texture before linear reuse")
end

T.section("Circular artwork reuses the ordinary native texture and static mask")
do
  local allocated = #statusBars
  local region = newRegion({orientation = "CLOCKWISE", startAngle = 90, endAngle = 270,
    foregroundTexture = "circular-artwork", foregroundColor = {0.2, 0.3, 0.4, 0.5},
    desaturateForeground = true, blendMode = "ADD", crop_x = 0.2, crop_y = 0.2,
    rotation = 27, auraRotation = 45, mirror = true, width = 320, height = 120})
  local primary, auxiliary = region.secretBar, region.secretAuxBar
  local texture, mask = region.secretTexture, region.secretMask
  T.expect(#statusBars == allocated + 2,
    "each region allocates only its primary source and linear EXTEND auxiliary")
  makeSecret(region)
  local color = last(texture, "SetVertexColor")
  T.expect(last(texture, "SetTexture")[1] == "circular-artwork"
      and last(texture, "SetDesaturated")[1] and texture:GetBlendMode() == "ADD" and color[4] == 0.5,
    "native circular artwork preserves texture, color, desaturation, and blending")
  T.expect(texture.masks[mask] and texture:IsShown() and mask:IsShown()
      and mask.allPoints == region.secretTextureFrame and not auxiliary:IsShown(),
    "circular progress uses the static region boundary without an auxiliary driver")
  T.expect(close(last(texture, "SetRotation")[1], math.rad(45))
      and close(last(mask, "SetRotation")[1], math.rad(45)),
    "circular artwork and its static mask receive the same direct aura rotation")
  region:SetOrientation("VERTICAL_INVERSE")
  T.expect(region.secretBar == primary and region.secretAuxBar == auxiliary and #statusBars == allocated + 2,
    "switching to linear rendering preserves all allocated drivers")
  local pivot = last(mask, "SetRotation")[2]
  T.expect(texture.masks[mask] and texture.radialPercent == nil
      and close(last(texture, "SetRotation")[1], math.rad(45))
      and close(last(mask, "SetRotation")[1], math.rad(45)) and pivot.x == 0 and pivot.y == 1,
    "same-angle linear transition retains direct rotation and selects the fixed mask corner")
  local textureRotations, maskRotations = #texture.calls.SetRotation, #mask.calls.SetRotation
  region:PreShow()
  T.expect(#texture.calls.SetRotation == textureRotations and #mask.calls.SetRotation == maskRotations,
    "linear PreShow preserves direct rotation without reapplying transforms")
  color = last(primary, "SetStatusBarColor")
  T.expect(color[4] == 0 and last(primary, "SetRenderMode")[1] == E.StatusBarRenderMode.Linear,
    "the primary remains a transparent linear progress source")
  region:SetOrientation("ANTICLOCKWISE")
  T.expect(texture.masks[mask] and texture.radialPercent ~= nil and region.FrameTick
      and close(last(texture, "SetRotation")[1], math.rad(45))
      and close(last(mask, "SetRotation")[1], math.rad(45)) and #statusBars == allocated + 2,
    "same-angle circular return restores native clipping and direct rotation without allocations")
end

T.section("Circular mode releases the compressed slant auxiliary")
do
  local region = newRegion({compress = true, slanted = true, slantMode = "EXTEND", slant = 0.3,
    smoothProgress = true, width = 240, height = 120})
  local primary, auxiliary = region.secretBar, region.secretAuxBar
  region.minProgress, region.maxProgress = 50, 100
  makeSecret(region)
  T.expect(region.usesSlantExtension and auxiliary:IsShown(), "compressed EXTEND activates the auxiliary driver")
  assertForwarded(auxiliary, region, "EXTEND auxiliary")
  region.durationObject = {durationObject = true}
  region:UpdateDuration()
  T.expect(primary.timer == region.durationObject and auxiliary.timer == region.durationObject,
    "compressed EXTEND forwards duration objects to both edge drivers")
  region:SetOrientation("CLOCKWISE")
  T.expect(primary.timer == region.durationObject and not auxiliary.timer and region.FrameTick
      and not region.usesSlantExtension and not auxiliary:IsShown(),
    "circular duration detaches and hides the unused auxiliary timer")
  makeSecret(region)
  region:SetInverse(true)
  assertForwarded(primary, region, "inverted circular source")
  T.expect(not primary.timer and not auxiliary.timer and region.FrameTick,
    "circular numeric values detach the old timer and retain geometry ticking")
  region:SetOrientation("VERTICAL_INVERSE")
  T.expect(region.usesSlantExtension and not region.FrameTick and auxiliary:IsShown(),
    "returning to EXTEND releases circular ticking and restores its auxiliary")
  assertForwarded(primary, region, "linear primary after circular mode")
  assertForwarded(auxiliary, region, "EXTEND auxiliary after circular rendering")
  T.expect(last(primary, "SetToTargetValue") and last(auxiliary, "SetToTargetValue"),
    "returning to EXTEND aligns both edge interpolation targets")
end
T.section("Progress updates preserve configured rendering and subscriptions")
for _, options in ipairs({
  {orientation = "HORIZONTAL"}, {orientation = "HORIZONTAL_INVERSE"},
  {orientation = "VERTICAL"}, {orientation = "VERTICAL_INVERSE"},
  {orientation = "CLOCKWISE"}, {orientation = "ANTICLOCKWISE"},
  {orientation = "HORIZONTAL", compress = true, slanted = true, slant = 0.3, slantMode = "EXTEND"},
}) do
  local region = newRegion(options)
  local label = options.orientation .. (options.compress and " compressed EXTEND" or "")
  makeSecret(region)
  region:SetInverse(true)
  local configuration, subscriptions = configurationCalls(region), subscriptionCalls(region)
  local ticker = region.FrameTick
  region.minProgress, region.maxProgress = newproxy(secret), newproxy(secret)
  makeSecret(region)
  assertForwarded(region.secretBar, region, label .. " subsequent update")
  T.expect(region.secretProgress == "value" and configurationCalls(region) == configuration,
    label .. " new numeric progress preserves anchors, artwork, and interpolation state")
  T.expect(subscriptionCalls(region) == subscriptions and region.FrameTick == ticker,
    label .. " new numeric progress keeps its existing frame subscription")
  if region.circular then
    T.expect(rawequal(last(region.secretTexture, "SetRadialProgressBarPercent")[1], region.secretFillFrame:GetWidth()),
      label .. " forwards native fractions alongside source value updates")
  end

  region.durationObject = {durationObject = true}
  region:UpdateDuration()
  configuration, subscriptions = configurationCalls(region), subscriptionCalls(region)
  region.durationObject = {durationObject = true}
  region.inverse = true
  region:UpdateDuration()
  T.expect(region.secretProgress == "duration" and region.secretBar.timer == region.durationObject
      and (not region.usesSlantExtension or region.secretAuxBar.timer == region.durationObject),
    label .. " forwards a replacement duration object to every active driver")
  T.expect(last(region.secretBar, "SetTimerDuration")[3] == E.StatusBarTimerDirection.RemainingTime,
    label .. " updates timer direction after trigger inversion without rebuilding geometry")
  T.expect(configurationCalls(region) == configuration,
    label .. " replacement duration preserves configured anchors and artwork")
  T.expect(subscriptionCalls(region) == subscriptions and (region.FrameTick ~= nil) == region.circular,
    label .. " replacement duration does not churn frame subscriptions")
end

T.section("Source changes and live dimensions refresh required configuration")
do
  local region = newRegion({orientation = "VERTICAL", width = 240, height = 120})
  makeSecret(region)
  region:SetInverse(true)
  T.expect(not region.secretFillFrame.allPoints,
    "inverse numeric values use complementary geometry")
  region.durationObject = {durationObject = true}
  region:UpdateDuration()
  T.expect(region.secretFillFrame.allPoints == region.secretBar:GetStatusBarTexture()
      and not last(region.secretBar, "SetReverseFill")[1],
    "duration replaces the complementary mask with direct geometry without changing the linear bar mode")
  T.expect(last(region.secretBar, "SetTimerDuration")[3] == E.StatusBarTimerDirection.ElapsedTime,
    "duration inversion is performed by native timer direction")
  makeSecret(region)
  T.expect(not region.secretFillFrame.allPoints and last(region.secretBar, "SetReverseFill")[1]
      and not region.secretBar.timer,
    "numeric progress restores complementary geometry and detaches the previous duration timer")
  region:SetRegionWidth(320)
  region:SetRegionHeight(160)
  region:Scale(0.5, 1.5)
  T.expect(region.secretBar:GetWidth() == 160 and region.secretBar:GetHeight() == 240,
    "linear driver follows changed region dimensions and scale")
  region:SetOrientation("CLOCKWISE")
  local vertexBefore = region.secretTexture.vertices[1][1]
  region:SetRegionWidth(280)
  region:Scale(1.5, 0.75)
  T.expect(region.secretBar:GetWidth() == 65536 and last(region.secretFillFrame, "SetScale")[1] == 65536
      and region.secretTexture.vertices[1][1] ~= vertexBefore
      and region.secretMask.allPoints == region.secretTextureFrame and not region.secretAuxBar:IsShown(),
    "circular resize updates public artwork vertices while preserving native fraction units")
  region:SetInverse(false)
  assertForwarded(region.secretBar, region, "direct circular progress after resize")
end

T.section("Native transitions cancel ordinary smoothing and restore ticks")
do
  local region = newRegion({smoothProgress = true})
  region:UpdateValue()
  local smoothingFrame = Private.frames["Smooth Status Bars"]
  T.expect(smoothingFrame:IsShown(), "ordinary progress queues smoothing")
  makeSecret(region)
  T.expect(not smoothingFrame:IsShown(), "entering native mode cancels queued ordinary smoothing")
  local before = region.foreground.endProgress
  smoothingFrame.scripts.OnUpdate()
  T.expect(region.foreground.endProgress == before, "stale smooth update cannot crop native foreground")
  region.useSmoothProgress = false
  region.value, region.total = 60, 100
  region:UpdateValue()
  T.expect(not region.secretProgress and close(region.progress, 0.6), "ordinary values restore ordinary geometry")
  T.expect(not region.secretTexture:IsShown() and not region.secretMask:IsShown(), "leaving native mode hides the native texture and mask")
  region.progressType, region.duration, region.expirationTime, region.paused = "timed", 20, 110, false
  region:UpdateTime()
  T.expect(region.FrameTick and region.subRegionEvents.subscribers.FrameTick == region,
    "ordinary timed progress restores its frame subscription")
  region.durationObject = {durationObject = true}
  region:UpdateDuration()
  T.expect(not region.FrameTick and not region.subRegionEvents.subscribers.FrameTick,
    "native duration removes the old ordinary frame subscription")
  region:UpdateTime()
  T.expect(region.FrameTick and close(region.progress, 0.5), "timed progress works again after a duration object")
end

do
  local region = newRegion({orientation = "CLOCKWISE", compress = true, slanted = true,
    slantMode = "EXTEND", slant = 0.3, smoothProgress = true})
  makeSecret(region)
  region:SetInverse(true)
  local function snaps(bar) return #(bar.calls.SetToTargetValue or {}) end
  local previousPrimarySnaps, previousAuxiliarySnaps = snaps(region.secretBar), snaps(region.secretAuxBar)
  region:SetOrientation("HORIZONTAL")
  local primarySnaps, extensionSnaps = snaps(region.secretBar), snaps(region.secretAuxBar)
  T.expect(primarySnaps > previousPrimarySnaps and extensionSnaps > previousAuxiliarySnaps,
    "entering compressed EXTEND aligns primary and extension interpolation targets")
  assertForwarded(region.secretAuxBar, region, "compressed EXTEND extension")
  region.value = newproxy(secret)
  region:UpdateValue()
  T.expect(snaps(region.secretBar) == primarySnaps and snaps(region.secretAuxBar) == extensionSnaps,
    "later compressed EXTEND values retain interpolation without snapping")
  T.expect(last(region.secretBar, "SetValue")[2] == E.StatusBarInterpolation.ExponentialEaseOut
      and last(region.secretAuxBar, "SetValue")[2] == E.StatusBarInterpolation.ExponentialEaseOut,
    "compressed EXTEND interpolates both native drivers consistently")
end

T.section("Native overlays and region reuse")
do
  local region, data = newRegion()
  region:UpdateValue()
  region:SetAdditionalProgress({{min = 25, max = 40}}, 0, 100, false)
  T.expect(region.extraTextures[1].visible, "ordinary overlay is visible")
  makeSecret(region)
  T.expect(not region.extraTextures[1].visible, "native transition hides a stale ordinary overlay")
  region:SetAdditionalProgress({{min = newproxy(secret), max = newproxy(secret)}}, newproxy(secret), newproxy(secret), false)
  T.expect(not region.extraTextures[1].visible, "secret overlay inputs cannot reach texture arithmetic")
  region:SetOrientation("CLOCKWISE")
  region:SetInverse(true)
  registration.modify(region.parent, region, data)
  T.expect(not region.secretProgress and not region.FrameTick and not region.subRegionEvents.subscribers.FrameTick,
    "reuse clears native mode and its frame subscription")
  T.expect(not region.secretBar:IsShown() and not region.secretAuxBar:IsShown()
      and not region.secretTexture:IsShown() and not region.secretMask:IsShown(),
    "reuse hides native renderers and masks")
  T.expect(region.secretTexture.radialPercent == nil, "reuse clears radial clipping on the retained native artwork")
  T.expect(last(region.secretBar:GetStatusBarTexture(), "SetSnapToPixelGrid")[1] == false,
    "region reuse preserves the transparent source's disabled pixel snapping")
  region.value, region.total = 80, 100
  region:UpdateValue()
  region:SetAdditionalProgress({{min = 80, max = 90}}, 0, 100, false)
  T.expect(close(region.progress, 0.8) and region.extraTextures[1].visible,
    "reused region resumes ordinary progress and overlays")
end

T.section("Live native artwork setters")
for _, orientation in ipairs({"HORIZONTAL", "CLOCKWISE"}) do
  local region = newRegion({orientation = orientation, startAngle = 45, endAngle = 225,
    crop_x = .41, crop_y = .41, auraRotation = 90})
  makeSecret(region)
  local texture = region.secretTexture
  local function nativeColor()
    return last(texture, "SetVertexColor")
  end
  region:SetTexture("replacement-texture")
  T.expect(last(texture, "SetTexture")[1] == "replacement-texture", orientation .. " changes native artwork")
  region:Color(0.2, 0.3, 0.4, 0.5)
  local color = nativeColor()
  T.expect(color[1] == 0.2 and color[2] == 0.3 and color[3] == 0.4 and color[4] == 0.5,
    orientation .. " updates native foreground color")
  region:ColorAnim(0.6, 0.7, 0.8, 0.9)
  T.expect(nativeColor()[1] == 0.6, orientation .. " updates native animated color")
  region:ColorAnim()
  T.expect(nativeColor()[1] == 0.2, orientation .. " restores native base color after animation")
  region:SetForegroundDesaturated(true)
  T.expect(last(texture, "SetDesaturated")[1] == true, orientation .. " updates native desaturation")
  local coords = last(texture, "SetTexCoord")
  local vertex = texture.vertices[1][1]
  region:SetCropX(0.9)
  if region.circular then
    T.expect(not texture:IsShown() and region.secretCircularUnsupported,
      "circular X crop hides unsupported unequal crop until the matching Y update")
    region:SetCropY(0.9)
    T.expect(texture:IsShown() and not region.secretCircularUnsupported and canonicalUV(texture)
        and texture.vertices[1][1] ~= vertex, "matching circular crops update public vertices and restore the foreground")
  else
    T.expect(last(texture, "SetTexCoord")[1] ~= coords[1], orientation .. " updates native X crop")
    coords = last(texture, "SetTexCoord")
    region:SetCropY(0.8)
    T.expect(last(texture, "SetTexCoord")[2] ~= coords[2], orientation .. " updates native Y crop")
  end
  coords = last(texture, "SetTexCoord")
  vertex = texture.vertices[1][1]
  local reverse = last(texture, "SetRadialProgressBarReverse")
  region:SetMirror(true)
  T.expect(region.circular and canonicalUV(texture) and texture.vertices[1][1] ~= vertex
      and last(texture, "SetRadialProgressBarReverse")[1] ~= reverse[1]
      or not region.circular and last(texture, "SetTexCoord")[1] ~= coords[1], orientation .. " updates native mirroring")
  coords = last(texture, "SetTexCoord")
  vertex = texture.vertices[1][1]
  region:SetTexRotation(37)
  T.expect(region.circular and canonicalUV(texture) and texture.vertices[1][1] ~= vertex
      or not region.circular and last(texture, "SetTexCoord")[1] ~= coords[1], orientation .. " updates native texture rotation")
  region:SetAuraRotation(90)
  if region.circular then
    T.expect(close(last(texture, "SetRotation")[1], math.rad(90))
        and close(last(region.secretMask, "SetRotation")[1], math.rad(90)),
      "circular color, texture, crop, and rotation setters retain cached direct aura rotation")
    local origin = last(texture, "SetRadialProgressBarStartOffset")[1]
    region:SetAnimRotation(73)
    T.expect(close((last(texture, "SetRadialProgressBarStartOffset")[1] - origin) % 1, .1),
      "animated artwork rotation updates its native origin without requiring progress changes")
    region:SetAnimRotation(nil)
    T.expect(close(last(texture, "SetRadialProgressBarStartOffset")[1], origin),
      "ending artwork rotation restores the configured native origin")
  else
    T.expect(close(last(texture, "SetRotation")[1], math.rad(90))
        and close(last(region.secretMask, "SetRotation")[1], math.rad(90)),
      orientation .. " updates native artwork and mask rotation directly")
  end
end

T.section("Unequal circular crops warn without displaying incorrect native progress")
do
  local region, data = newRegion({uid = "old-crop-aura", crop_x = .2, crop_y = .4})
  local warningsBefore = #warningCalls
  makeSecret(region)
  T.expect(region.secretTexture:IsShown() and #warningCalls == warningsBefore,
    "unequal crops remain available for native linear rendering")
  region:SetOrientation("CLOCKWISE")
  local warning = warningCalls[#warningCalls]
  T.expect(not region.secretTexture:IsShown() and region.secretCircularUnsupported
      and warning.uid == "old-crop-aura" and warning.key == "secretCircularCrop"
      and warning.severity == "warning" and warning.message:find("equal Crop X and Crop Y", 1, true),
    "unequal native circular crops hide the foreground and explain the supported configuration")
  local warningCount = #warningCalls
  makeSecret(region)
  region:Color(.2, .3, .4, .5)
  region:SetInverse(true)
  T.expect(#warningCalls == warningCount and not region.secretTexture:IsShown(),
    "repeated updates neither repeat the warning nor reveal unsupported circular artwork")
  region:SetOrientation("HORIZONTAL")
  T.expect(region.secretTexture:IsShown() and not region.secretCircularUnsupported
      and warningCalls[#warningCalls].severity == nil,
    "returning to linear rendering restores the foreground and clears the crop warning")
  region:SetOrientation("CLOCKWISE")
  region:SetCropY(.2)
  T.expect(region.secretTexture:IsShown() and not region.secretCircularUnsupported
      and warningCalls[#warningCalls].severity == nil,
    "matching crops restore circular foreground without changing its progress source")
  region:SetCropX(.4)
  region.value, region.total = 25, 100
  region:UpdateValue()
  T.expect(not region.secretCircularUnsupported and region.foregroundSpinner.visible
      and warningCalls[#warningCalls].severity == nil,
    "ordinary circular values retain unequal-crop rendering and clear the native limitation warning")
  makeSecret(region)
  data.uid, data.orientation = "reused-crop-aura", "CLOCKWISE"
  registration.modify(region.parent, region, data)
  warning = warningCalls[#warningCalls]
  T.expect(warning.uid == "old-crop-aura" and warning.severity == nil
      and region.secretProgressUid == "reused-crop-aura",
    "region reuse clears the warning against the previous aura before replacing its identity")
  makeSecret(region)
  warning = warningCalls[#warningCalls]
  T.expect(warning.uid == "reused-crop-aura" and warning.severity == "warning",
    "a reused region reports unsupported crops against its new aura")
end

T.section("Circular crop warnings remain while another clone is unsupported")
do
  local options = {uid = "shared-crop-aura", orientation = "CLOCKWISE", crop_x = .2, crop_y = .4}
  local first, second = newRegion(options), newRegion(options)
  makeSecret(first)
  makeSecret(second)
  T.expect(first.secretCircularUnsupported and second.secretCircularUnsupported
      and warningCalls[#warningCalls].uid == "shared-crop-aura" and warningCalls[#warningCalls].severity == "warning",
    "two unsupported clones contribute to their shared aura warning")
  first.value, first.total = 25, 100
  first:UpdateValue()
  T.expect(not first.secretCircularUnsupported and second.secretCircularUnsupported
      and warningCalls[#warningCalls].uid == "shared-crop-aura" and warningCalls[#warningCalls].severity == "warning",
    "one clone returning to ordinary progress retains the warning for its unsupported sibling")
  second:SetCropY(.2)
  T.expect(second.secretTexture:IsShown() and not second.secretCircularUnsupported
      and warningCalls[#warningCalls].uid == "shared-crop-aura" and warningCalls[#warningCalls].severity == nil,
    "the shared warning clears when the final unsupported clone matches its crops")
end

T.section("Hidden and pooled clones release circular crop warning ownership")
do
  local options = {uid = "hidden-crop-aura", orientation = "CLOCKWISE", crop_x = .2, crop_y = .4}
  local first, second = newRegion(options), newRegion(options)
  first.toShow, second.toShow = true, true
  makeSecret(first)
  makeSecret(second)
  local function collapse(region)
    -- RegionPrototype marks toShow false before PreHide, then runs condition
    -- resets before Hide/ReleaseClone. Preserve the object like clonePool does.
    region.toShow = false
    region:PreHide()
    region:SetCropY(.2)
    region:SetCropY(.4)
    region:Hide()
  end
  collapse(first)
  T.expect(first.secretCircularUnsupported and warningCalls[#warningCalls].severity == "warning",
    "hiding one unsupported clone preserves its active sibling's warning")
  collapse(second)
  local pooled = {first, second}
  T.expect(pooled[1].secretCircularUnsupported and pooled[2].secretCircularUnsupported
      and warningCalls[#warningCalls].severity == nil,
    "hidden condition changes cannot restore warning ownership to retained pooled clones")
  second.toShow = true
  second:PreShow()
  second:Show()
  T.expect(warningCalls[#warningCalls].uid == "hidden-crop-aura" and warningCalls[#warningCalls].severity == "warning",
    "showing an unchanged unsupported clone restores its aura warning")
  second:SetCropY(.2)
  T.expect(warningCalls[#warningCalls].severity == nil and second.secretTexture:IsShown(),
    "fixing the only active clone clears the warning despite an unsupported pooled sibling")
  first.toShow = true
  first:PreShow()
  first:Show()
  T.expect(warningCalls[#warningCalls].severity == "warning",
    "a second pooled clone reclaims warning ownership only when shown again")
  collapse(first)
  T.expect(warningCalls[#warningCalls].severity == nil,
    "hiding the final unsupported clone clears the warning again")
end

T.section("Validated circular fixture parameters remain calibrated")
for _, fixture in ipairs({
  {orientation = "ANTICLOCKWISE", startAngle = 0, endAngle = 360, rotation = 47,
    width = 200, height = 200, origin = 227 / 360, finish = 0, reverse = true},
  {orientation = "CLOCKWISE", startAngle = 45, endAngle = 225, rotation = 57, auraRotation = 30,
    inverse = true, width = 240, height = 120, origin = 282 / 360, finish = .5, reverse = false},
}) do
  fixture.crop_x, fixture.crop_y = .41, .41
  local region = newRegion(fixture)
  makeSecret(region)
  T.expect(close(last(region.secretTexture, "SetRadialProgressBarStartOffset")[1], fixture.origin)
      and close(last(region.secretTexture, "SetRadialProgressBarEndOffset")[1], fixture.finish)
      and last(region.secretTexture, "SetRadialProgressBarReverse")[1] == fixture.reverse,
    fixture.orientation .. " reproduces the G02/G03 native origin, trim, and direction")
  for _, fraction in ipairs({0, .25, .5, .75, 1}) do
    region.secretFillFrame:SetWidth(fraction)
    region:FrameTick()
    T.expect(last(region.secretTexture, "SetRadialProgressBarPercent")[1] == fraction,
      fixture.orientation .. " forwards native normalized fraction " .. fraction .. " without a second inversion")
  end
end

T.section("RGB-only color animations retain ordinary alpha behavior")
for _, orientation in ipairs({"HORIZONTAL", "HORIZONTAL_INVERSE", "VERTICAL", "VERTICAL_INVERSE", "CLOCKWISE", "ANTICLOCKWISE"}) do
  local region = newRegion({orientation = orientation})
  region:Color(0.2, 0.3, 0.4, 0.35)
  region:ColorAnim(0.6, 0.7, 0.8)
  local ordinaryTexture = region.circular and region.foregroundSpinner.textures[1] or region.foreground.texture
  local ordinary = last(ordinaryTexture, "SetVertexColor")
  makeSecret(region)
  local function nativeColor()
    return last(region.secretTexture, "SetVertexColor")
  end
  local native = nativeColor()
  T.expect(ordinary[4] == 1 and native[1] == ordinary[1] and native[2] == ordinary[2]
      and native[3] == ordinary[3] and native[4] == ordinary[4],
    orientation .. " preserves RGB-only animation color and opaque alpha when entering native rendering")
  region:ColorAnim()
  native = nativeColor()
  T.expect(native[1] == 0.2 and native[2] == 0.3 and native[3] == 0.4
      and native[4] == 0.35,
    orientation .. " restores configured color and alpha when the animation ends")
  region:Color(.25, .35, .45, .55)
  region:ColorAnim(.65, .75, .85)
  region:SetForegroundDesaturated(true)
  region.value, region.total = 25, 100
  region:UpdateValue()
  ordinary = last(ordinaryTexture, "SetVertexColor")
  local activeRestored = ordinary[1] == .65 and ordinary[2] == .75 and ordinary[3] == .85
      and ordinary[4] == 1 and last(ordinaryTexture, "SetDesaturated")[1] == true
  makeSecret(region)
  region:ColorAnim()
  region:SetForegroundDesaturated(false)
  region.value, region.total = 25, 100
  region:UpdateValue()
  ordinary = last(ordinaryTexture, "SetVertexColor")
  T.expect(activeRestored and ordinary[1] == .25 and ordinary[2] == .35 and ordinary[3] == .45
      and ordinary[4] == .55 and last(ordinaryTexture, "SetDesaturated")[1] == false,
    orientation .. " restores active animation or reset base appearance and desaturation when ordinary rendering resumes")
end

T.section("Circular public geometry preserves ordinary artwork and angular progress")
for _, orientation in ipairs({"CLOCKWISE", "ANTICLOCKWISE"}) do
  for _, angles in ipairs({{0, 360}, {37, 397}, {90, 450}, {90, 270}}) do
    for _, size in ipairs({{200, 200}, {320, 120}}) do
    for _, scale in ipairs({{1, 1}, {-1.2, 1}, {1, -0.75}, {-1.2, -0.75}}) do
      local options = {orientation = orientation, startAngle = angles[1], endAngle = angles[2],
        width = size[1], height = size[2], crop_x = 0.41, crop_y = 0.41,
        rotation = 27, auraRotation = 23, mirror = true}
      local region = newRegion(options)
      options.startAngle, options.endAngle = 0, 360
      local reference = newRegion(options)
      reference.value, reference.total = 100, 100
      reference:UpdateValue()
      reference:Scale(scale[1], scale[2])
      region:Scale(scale[1], scale[2])
      local ordinary = last(reference.foregroundSpinner.textures[1], "SetTexCoord")
      local label = string.format("%s %d-%d at %dx%d scaled %g/%g", orientation, angles[1], angles[2], size[1], size[2], scale[1], scale[2])
      makeSecret(region)
      T.expect(artworkMatchesOrdinary(region, ordinary), label .. " maps public pixel samples to the ordinary artwork UVs")
      local origin = orientation == "CLOCKWISE" and region.startAngle or region.endAngle
      local nativeOrigin = 180 + last(region.secretTexture, "SetRadialProgressBarStartOffset")[1] * 360
      local nativeSpan = (1 - last(region.secretTexture, "SetRadialProgressBarEndOffset")[1]) * 360
      local nativeReverse = last(region.secretTexture, "SetRadialProgressBarReverse")[1]
      local correctRays, quad = true, artworkQuad(region)
      for _, fraction in ipairs({0, .25, .5, .75, 1}) do
        local nativeAngle = math.rad(nativeOrigin + (nativeReverse and -1 or 1) * nativeSpan * fraction)
        local x, y = quadPoint(quad, .5 + .2 * math.sin(nativeAngle), .5 - .2 * math.cos(nativeAngle))
        local expected = math.rad(origin + (orientation == "CLOCKWISE" and 1 or -1) * (region.endAngle - region.startAngle) * fraction)
        local dx, dy = math.sin(expected), -math.cos(expected)
        correctRays = correctRays and close((x - .5) * dy - (y - .5) * dx, 0)
            and (x - .5) * dx + (y - .5) * dy > 0
      end
      T.expect(correctRays, label .. " preserves the start and every quarter-progress ray through mirroring and artwork rotation")
      local mask = region.secretMask
      local maskReset = canonicalUV(mask) and mask.allPoints == region.secretTextureFrame
      for _, offset in pairs(mask.vertices) do maskReset = maskReset and offset[1] == 0 and offset[2] == 0 end
      T.expect(maskReset and close(last(mask, "SetRotation")[1], math.rad(23))
          and close(last(region.secretTexture, "SetRotation")[1], math.rad(23)),
        label .. " retains a static canonical region mask with matching direct aura rotation")
      makeSecret(region)
      region:SetInverse(true)
      region:FrameTick()
      T.expect(artworkMatchesOrdinary(region, ordinary)
          and close(last(region.secretTexture, "SetRadialProgressBarStartOffset")[1] * 360 + 180, nativeOrigin),
        label .. " keeps amount inversion out of artwork and sweep orientation")
      region.durationObject = {durationObject = true}
      region:UpdateDuration()
      T.expect(region.FrameTick and artworkMatchesOrdinary(region, ordinary), label .. " preserves artwork while forwarding native timer fractions")
      region.secretFillFrame:SetWidth(newproxy(secret))
      region:PreShow()
      T.expect(artworkMatchesOrdinary(region, ordinary)
          and close(last(region.secretTexture, "SetRotation")[1], math.rad(23))
          and rawequal(last(region.secretTexture, "SetRadialProgressBarPercent")[1], region.secretFillFrame:GetWidth()),
        label .. " preserves direct rotation and refreshes native progress when shown again")
    end
    end
  end
end

T.section("Public linear shape matches the existing coordinate renderer")
for _, orientation in ipairs({"HORIZONTAL", "HORIZONTAL_INVERSE", "VERTICAL", "VERTICAL_INVERSE"}) do
  for _, compress in ipairs({false, true}) do
    for _, slantMode in ipairs({"INSIDE", "EXTEND"}) do
      for _, slantFirst in ipairs({false, true}) do
        local region = newRegion({orientation = orientation, compress = compress, slanted = true,
          slant = 0.3, slantMode = slantMode, slantFirst = slantFirst, width = 240, height = 120,
          crop_x = 0.2, crop_y = 0.6, rotation = 27, mirror = true, user_x = 0.15, user_y = -0.1})
        local geometryOK, coverageOK, artworkOK, details = true, true, true, ""
        for _, inverse in ipairs({false, true}) do
          for _, amount in ipairs({0, 0.25, 0.5, 0.75, 1}) do
            region.inverseDirection, region.value = inverse, amount * 100
            region.secretProgress = "value"
            region:SetProgressSecret()
            local progress = inverse and 1 - amount or amount
            local horizontal = orientation:find("HORIZONTAL") ~= nil
            local reverse = orientation:find("INVERSE") ~= nil
            local width = region.width * (compress and horizontal and progress or 1)
            local height = region.height * (compress and not horizontal and progress or 1)
            local left = compress and horizontal and reverse and region.width - width or 0
            local top = compress and not horizontal and not reverse and region.height - height or 0
            local shape = {width = width, height = height, slant = 0.3, slantFirst = slantFirst,
              slantMode = slantMode, coord = Private.TextureCoords.create(frame("Texture"))}
            region.foreground.ApplyProgressToCoord(shape, 0, compress and 1 or progress)
            local polygon = maskPolygon(region.secretMask)
            local textureLeft, textureTop, textureWidth, textureHeight = rectangle(region.secretTexture)
            local positions = {}
            for vertex, corner in ipairs(corners) do
              local actual = polygon[vertex]
              local expectedX = left + shape.coord[corner[1] .. "x"] * width
              local expectedY = top + shape.coord[corner[1] .. "y"] * height
              positions[vertex] = {expectedX, expectedY}
              if math.abs(actual[1] - expectedX) > 0.025 or math.abs(actual[2] - expectedY) > 0.025 then
                geometryOK = false
                if details == "" then
                  details = string.format(" (amount %.2f, inverse %s, %s: %.2f,%.2f != %.2f,%.2f)",
                    amount, tostring(inverse), corner[1], actual[1], actual[2], expectedX, expectedY)
                end
              end
              if expectedX < textureLeft - 0.025 or expectedX > textureLeft + textureWidth + 0.025
                or expectedY < textureTop - 0.025 or expectedY > textureTop + textureHeight + 0.025
              then
                coverageOK = false
              end
            end
            shape.coord:Transform(region.crop_x, region.crop_y, region.effectiveTexRotation or region.texRotation,
              region.mirror, false, region.user_x, region.user_y)
            local uv = last(region.secretTexture, "SetTexCoord")
            if textureWidth > 0 and textureHeight > 0 then
              for vertex, corner in ipairs(corners) do
                local u = (positions[vertex][1] - textureLeft) / textureWidth
                local v = (positions[vertex][2] - textureTop) / textureHeight
                local x = uv[1] + (uv[5] - uv[1]) * u + (uv[3] - uv[1]) * v
                local y = uv[2] + (uv[6] - uv[2]) * u + (uv[4] - uv[2]) * v
                if not close(x, shape.coord[corner[1] .. "x"]) or not close(y, shape.coord[corner[1] .. "y"]) then
                  artworkOK = false
                end
              end
            end
          end
        end
        local label = orientation .. "/" .. (compress and "compressed" or "uncompressed")
          .. "/" .. slantMode .. "/" .. (slantFirst and "first" or "second")
        T.expect(geometryOK, label .. " matches ordinary slant at empty, quarter, half, three-quarter, and full progress" .. details)
        T.expect(coverageOK, label .. " keeps artwork beneath the entire visible mask")
        T.expect(artworkOK, label .. " preserves cropped, mirrored, rotated, and shifted artwork coordinates")
      end
    end
  end
end

T.section("Exported vertical inverse aura rotates its mask around the region center")
do
  local options = {orientation = "VERTICAL", width = 240, height = 120, inverse = true,
    compress = false, auraRotation = 30, crop_x = .41, crop_y = .41, slant = 0}
  local region, ordinary = newRegion(options), newRegion(options)
  local function rotate(texture, points)
    local left, top, width, height = rectangle(texture)
    local rotation = last(texture, "SetRotation")
    local pivot = rotation[2]
    local x = left + width * (pivot and pivot.x or .5)
    -- Bottom-up pivot Y was identified from the recorded drift and the user
    -- confirmed the correction in-game; model checks alone cannot establish it.
    local y = top + height * (pivot and (1 - pivot.y) or .5)
    local cosine, sine = math.cos(rotation[1]), math.sin(rotation[1])
    for _, point in ipairs(points) do
      local dx, dy = point[1] - x, point[2] - y
      point[1], point[2] = x + cosine * dx + sine * dy, y - sine * dx + cosine * dy
    end
    return points
  end
  local function matchesOrdinary(value)
    region.value, region.secretProgress = value * 100, "value"
    region:SetProgressSecret()
    ordinary.value = value * 100
    ordinary:UpdateValue()
    local texture = ordinary.foreground.texture
    local left, top, width, height = rectangle(texture)
    local expected = {}
    for vertex, corner in ipairs(corners) do
      local offset = texture.vertices[vertex]
      expected[vertex] = {left + corner[2] * width + offset[1], top + corner[3] * height - offset[2]}
    end
    expected = rotate(texture, expected)
    local actual = rotate(region.secretMask, maskPolygon(region.secretMask))
    for vertex, point in ipairs(expected) do
      -- The secret clipping mask deliberately extends its top-left by .01.
      if math.abs(actual[vertex][1] - point[1]) > .025 or math.abs(actual[vertex][2] - point[2]) > .025 then
        return false
      end
    end
    return close(last(region.secretTexture, "SetRotation")[1], last(texture, "SetRotation")[1])
  end
  for _, value in ipairs({.25, .5, .75}) do
    T.expect(matchesOrdinary(value), "rotated native mask matches ordinary vertices at source progress " .. value)
  end
  for _, target in ipairs({region, ordinary}) do
    target:SetRegionWidth(300)
    target:SetRegionHeight(160)
    target:SetAuraRotation(-20)
  end
  T.expect(matchesOrdinary(.5), "size and angle changes refresh the public mask pivot offsets")
end

T.section("Animated native appearance changes preserve unrelated state")
for _, options in ipairs({
  {orientation = "HORIZONTAL"},
  {orientation = "HORIZONTAL", compress = true, slanted = true, slant = .3, slantMode = "EXTEND"},
  {orientation = "CLOCKWISE", crop_x = .41, crop_y = .41},
}) do
  local region = newRegion(options)
  makeSecret(region)
  local label = options.orientation .. (options.compress and " EXTEND" or "")
  local function ordinaryAppearanceWrites()
    local count = 0
    for _, texture in ipairs({region.foreground.texture, unpack(region.foregroundSpinner.textures)}) do
      count = count + #(texture.calls.SetVertexColor or {}) + #(texture.calls.SetDesaturated or {})
    end
    return count
  end
  for _, operation in ipairs({
    {"color", function(i) region:Color(.1 + i / 100, .3, .4, .5) end,
      "SetVertexColor", 60, {SetVertexColor = true}},
    {"animated color", function(i) region:ColorAnim(.1 + i / 100, .3, .4, .5) end,
      "SetVertexColor", 60, {SetVertexColor = true}},
    {"desaturation", function(i) region:SetForegroundDesaturated(i % 2 == 0) end,
      "SetDesaturated", 60, {SetDesaturated = true}},
    {"aura rotation", function(i) region:SetAuraRotation(i) end, "SetRotation", 120,
      {SetRotation = true, SetPoint = true}},
  }) do
    local before, objectsBefore, ordinaryBefore = nativeCalls(region), frameObjects, ordinaryAppearanceWrites()
    for i = 1, 60 do operation[2](i) end
    local after, unchanged = nativeCalls(region), true
    for name, count in pairs(after) do
      if not operation[5][name] and count ~= (before[name] or 0) then unchanged = false end
    end
    T.expect(unchanged and after[operation[3]] - (before[operation[3]] or 0) == operation[4]
        and frameObjects == objectsBefore and ordinaryAppearanceWrites() == ordinaryBefore,
      label .. " 60 " .. operation[1] .. " updates change native state without new objects or dormant foreground appearance writes")
  end

  for _, duration in ipairs({false, true}) do
    if duration then
      region.durationObject = {durationObject = true}
      region:UpdateDuration()
    end
    local before, objectsBefore = nativeCalls(region), frameObjects
    for i = 1, 60 do region:Scale(1 + i / 100, 1 + i / 200) end
    local after, unchanged = nativeCalls(region), true
    for _, name in ipairs({"SetMinMaxValues", "SetValue", "SetTimerDuration", "SetToTargetValue",
        "SetTexture", "SetAtlas", "SetBlendMode", "SetDesaturated", "SetVertexColor"}) do
      if (after[name] or 0) ~= (before[name] or 0) then unchanged = false end
    end
    T.expect(unchanged and frameObjects == objectsBefore,
      label .. " scale animation preserves " .. (duration and "timer" or "numeric") .. " progress and texture assets")
  end

  if region.circular then
    local reads, fraction = 0, newproxy(secret)
    region.secretFillFrame.GetWidth = function() reads = reads + 1; return fraction end
    local before, objectsBefore = nativeCalls(region), frameObjects
    for i = 1, 60 do region:FrameTick() end
    local after, unchanged = nativeCalls(region), true
    for name, count in pairs(after) do
      if name ~= "SetRadialProgressBarPercent" and count ~= (before[name] or 0) then unchanged = false end
    end
    T.expect(unchanged and reads == 60 and after.SetRadialProgressBarPercent - before.SetRadialProgressBarPercent == 60
        and frameObjects == objectsBefore and rawequal(last(region.secretTexture, "SetRadialProgressBarPercent")[1], fraction),
      "circular ticks read one secret width and forward one native percent without creating objects")
  end
end

T.finish()
