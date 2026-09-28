if not M33kAuras.IsLibsOK() then return end
---@type string
local AddonName = ...
---@class Private
local Private = select(2, ...)

local L = M33kAuras.L;

local defaultFont = M33kAuras.defaultFont
local defaultFontSize = M33kAuras.defaultFontSize

-- Credit to CommanderSirow for taking the time to properly craft the TransformPoint function
-- to the enhance the abilities of Progress Textures.
-- Also Credit to Semlar for explaining how circular progress can be shown

-- NOTES:
--  Most SetValue() changes are quite equal (among compress/non-compress)
--  (There is no GUI button for mirror_v, but mirror_h)
--  New/Used variables
--   region.user_x (0) - User defined center x-shift [-1, 1]
--   region.user_y (0) - User defined center y-shift [-1, 1]
--   region.mirror_v (false) - Mirroring along x-axis [bool]
--   region.mirror_h (false) - Mirroring along y-axis [bool]
--   region.scale (1.0) - user defined scaling [1, INF]
--   region.full_rotation (false) - Allow full rotation [bool]

local default = {
  progressSource = {-1, "" },
  adjustedMax = "",
  adjustedMin = "",
  foregroundTexture = "Interface\\Addons\\M33kAuras\\PowerAurasMedia\\Auras\\Aura3",
  backgroundTexture = "Interface\\Addons\\M33kAuras\\PowerAurasMedia\\Auras\\Aura3",
  desaturateBackground = false,
  desaturateForeground = false,
  sameTexture = true,
  compress = false,
  blendMode = "BLEND",
  textureWrapMode = "CLAMPTOBLACKADDITIVE",
  backgroundOffset = 2,
  width = 200,
  height = 200,
  orientation = "VERTICAL",
  inverse = false,
  foregroundColor = {1, 1, 1, 1},
  backgroundColor = {0.5, 0.5, 0.5, 0.5},
  startAngle = 0,
  endAngle = 360,
  user_x = 0,
  user_y = 0,
  crop_x = 0.41,
  crop_y = 0.41,
  rotation = 0, -- Uses tex coord rotation, called "legacy rotation" in the ui and texRotation in code everywhere else
  auraRotation = 0, -- Uses texture:SetRotation
  selfPoint = "CENTER",
  anchorPoint = "CENTER",
  anchorFrameType = "SCREEN",
  xOffset = 0,
  yOffset = 0,
  font = defaultFont,
  fontSize = defaultFontSize,
  mirror = false,
  frameStrata = 1,
  slantMode = "INSIDE"
};

Private.regionPrototype.AddAlphaToDefault(default);

Private.regionPrototype.AddProgressSourceToDefault(default)

local screenWidth, screenHeight = math.ceil(GetScreenWidth() / 20) * 20, math.ceil(GetScreenHeight() / 20) * 20;

local properties = {
  desaturateForeground = {
    display = L["Desaturate Foreground"],
    setter = "SetForegroundDesaturated",
    type = "bool",
  },
  desaturateBackground = {
    display = L["Desaturate Background"],
    setter = "SetBackgroundDesaturated",
    type = "bool",
  },
  foregroundColor = {
    display = L["Foreground Color"],
    setter = "Color",
    type = "color"
  },
  foregroundColorFromBoolean = {
    display = L["Foreground Color"] .. " (Boolean)",
    setter = "Color",
    type = "color",
    colorFromBoolean = true,
    baseProperty = "foregroundColor",
    resetFallback = {1, 0, 0, 1},
    default = {
      checks = {
        {
          trigger = -1,
          variable = "alwaystrue",
          color = {1, 0, 0, 1},
          when = true,
        },
      },
    },
  },
  backgroundColor = {
    display = L["Background Color"],
    setter = "SetBackgroundColor",
    type = "color"
  },
  backgroundColorFromBoolean = {
    display = L["Background Color"] .. " (Boolean)",
    setter = "SetBackgroundColor",
    type = "color",
    colorFromBoolean = true,
    baseProperty = "backgroundColor",
    resetFallback = {1, 0, 0, 1},
    default = {
      checks = {
        {
          trigger = -1,
          variable = "alwaystrue",
          color = {1, 0, 0, 1},
          when = true,
        },
      },
    },
  },
  width = {
    display = L["Width"],
    setter = "SetRegionWidth",
    type = "number",
    min = 1,
    softMax = screenWidth,
    bigStep = 1,
    default = 32
  },
  height = {
    display = L["Height"],
    setter = "SetRegionHeight",
    type = "number",
    min = 1,
    softMax = screenHeight,
    bigStep = 1,
    default = 32
  },
  orientation = {
    display = L["Orientation"],
    setter = "SetOrientation",
    type = "list",
    values = Private.orientation_with_circle_types
  },
  auraRotation = {
    display = L["Rotation"],
    setter = "SetAuraRotation",
    type = "number",
    min = 0,
    max = 360,
    bigStep = 10,
    default = 0
  },
  inverse = {
    display = L["Inverse"],
    setter = "SetInverse",
    type = "bool"
  },
  mirror = {
    display = L["Mirror"],
    setter = "SetMirror",
    type = "bool",
  },
  rotation = {
    display = L["Texture Rotation"],
    setter = "SetTexRotation",
    type = "number",
    min = 0,
    max = 360,
    bigStep = 1,
    default = 0
  },
  crop_x = {
    display = L["Crop X"],
    setter = "SetCropX",
    type = "number",
    min = 0,
    softMax = 2,
    bigStep = 0.01,
    isPercent = true,
  },
  crop_y = {
    display = L["Crop Y"],
    setter = "SetCropY",
    type = "number",
    min = 0,
    softMax = 2,
    bigStep = 0.01,
    isPercent = true,
  },
}

Private.regionPrototype.AddProperties(properties, default);

local function GetProperties(data)
  local overlayInfo = Private.GetOverlayInfo(data);
  local auraProperties = CopyTable(properties)
  auraProperties.progressSource.values = Private.GetProgressSourcesForUi(data)
  if (overlayInfo and next(overlayInfo)) then
    for id, display in ipairs(overlayInfo) do
      auraProperties["overlays." .. id] = {
        display = string.format(L["%s Overlay Color"], display),
        setter = "SetOverlayColor",
        arg1 = id,
        type = "color",
      }
    end
    return auraProperties
  else
    return auraProperties
  end
end


local TextureSetValueFunction = function(self, progress)
  self.progress = progress;
  progress = max(0, progress);
  progress = min(1, progress);
  self.foreground:SetValue(0, progress);
end

local CircularSetValueFunctions = {
  ["CLOCKWISE"] = function(self, progress)
    local startAngle = self.startAngle;
    local endAngle = self.endAngle;
    progress = progress or 0;
    self.progress = progress;

    if (progress < 0) then
      progress = 0;
    end

    if (progress > 1) then
      progress = 1;
    end

    local pAngle = (endAngle - startAngle) * progress + startAngle;
    self.foregroundSpinner:SetProgress(startAngle, pAngle);
  end,
  ["ANTICLOCKWISE"] = function(self, progress)
    local startAngle = self.startAngle;
    local endAngle = self.endAngle;
    progress = progress or 0;
    self.progress = progress;

    if (progress < 0) then
      progress = 0;
    end

    if (progress > 1) then
      progress = 1;
    end
    progress = 1 - progress;

    local pAngle = (endAngle - startAngle) * progress + startAngle;
    self.foregroundSpinner:SetProgress(pAngle, endAngle);
  end
}

local function hideExtraTextures(extraTextures, from)
  for i = from, #extraTextures do
    extraTextures[i]:Hide();
  end
end

local function ensureExtraTextures(region, count)
  local auraRotationRadians = region.auraRotation / 180 * math.pi
  for i = #region.extraTextures + 1, count do
    local extraTexture = Private.LinearProgressTextureBase.create(region, "ARTWORK", min(i, 7));
    Private.LinearProgressTextureBase.modify(extraTexture, {
      offset = 0,
      blendMode = region.foreground:GetBlendMode(),
      desaturated = false,
      auraRotation = auraRotationRadians,
      texture = region.currentTexture,
      textureWrapMode = region.textureWrapMode,
      crop_x = region.crop_x,
      crop_y = region.crop_y,
      user_x = region.user_x,
      user_y = region.user_y,
      mirror = region.mirror,
      texRotation = region.effectiveTexRotation,
      width = region.width,
      height = region.height
    })
    extraTexture:SetOrientation(region.orientation, region.compress, region.slanted, region.slant,
                                region.slantFirst, region.slantMode)
    region.extraTextures[i] = extraTexture;
  end
end

local function ensureExtraSpinners(region, count)
  local auraRotationRadians = region.auraRotation / 180 * math.pi
  for i = #region.extraSpinners + 1, count do
    local extraSpinner = Private.CircularProgressTextureBase.create(region, "OVERLAY", min(i, 7))
    Private.CircularProgressTextureBase.modify(extraSpinner, {
      crop_x = region.crop_x,
      crop_y = region.crop_y,
      mirror = region.mirror,
      texRotation = region.effectiveTexRotation,
      texture = region.currentTexture,
      blendMode = region.foreground:GetBlendMode(),
      desaturated = false,
      auraRotation = auraRotationRadians,
      width = region.width,
      height = region.height,
      offset = 0
    })

    extraSpinner:SetScale(region.scalex, region.scaley)

    region.extraSpinners[i] = extraSpinner
  end
end

local function convertToProgress(rprogress, additionalProgress, adjustMin, totalWidth, inverse, clamp)
  if hasanysecretvalues(additionalProgress.min, additionalProgress.max,
                        additionalProgress.width, additionalProgress.offset) then
    return 0, 0;
  end
  local startProgress = 0;
  local endProgress = 0;

  if (additionalProgress.min and additionalProgress.max) then
    if (totalWidth ~= 0) then
      startProgress = (additionalProgress.min - adjustMin) / totalWidth;
      endProgress = (additionalProgress.max - adjustMin) / totalWidth;

      if (inverse) then
        startProgress = 1 - startProgress;
        endProgress = 1 - endProgress;
      end
    end
  elseif (additionalProgress.direction) then
    local forwardDirection = (additionalProgress.direction or "forward") == "forward";
    if (inverse) then
      forwardDirection = not forwardDirection;
    end
    local width = additionalProgress.width or 0;
    local offset = additionalProgress.offset or 0;
    if (width ~= 0) then
      if (forwardDirection) then
        startProgress = rprogress + offset / totalWidth ;
        endProgress = rprogress + (offset + width) / totalWidth;
      else
        startProgress = rprogress - (width + offset) / totalWidth;
        endProgress = rprogress - offset / totalWidth;
      end
    end
  end

  if (clamp) then
    startProgress = max(0, min(1, startProgress));
    endProgress = max(0, min(1, endProgress));
  end

  return startProgress, endProgress;
end

local function ApplyAdditionalProgressLinear(self, additionalProgress, min, max, inverse)
  self.additionalProgress = additionalProgress;
  self.additionalProgressMin = min;
  self.additionalProgressMax = max;
  self.additionalProgressInverse = inverse;

  local effectiveInverse = (inverse and not self.inverseDirection) or (not inverse and self.inverseDirection);

  if (additionalProgress) then
    ensureExtraTextures(self, #additionalProgress);
    local totalWidth = max - min;
    for index, additionalProgress in ipairs(additionalProgress) do
      local extraTexture = self.extraTextures[index];

      local startProgress, endProgress = convertToProgress(self.progress, additionalProgress, min,
                                                           totalWidth, effectiveInverse, self.overlayclip)
      if ((endProgress - startProgress) == 0) then
        extraTexture:Hide();
      else
        extraTexture:Show();
        local color = self.overlays[index];
        if (color) then
          extraTexture:SetColor(unpack(color));
        else
          extraTexture:SetColor(1, 1, 1, 1);
        end

        extraTexture:SetValue(startProgress, endProgress)
      end
    end

    hideExtraTextures(self.extraTextures, #additionalProgress + 1);
  else
    hideExtraTextures(self.extraTextures, 1);
  end
end

local function ApplyAdditionalProgressCircular(self, additionalProgress, min, max, inverse)
  self.additionalProgress = additionalProgress;
  self.additionalProgressMin = min;
  self.additionalProgressMax = max;
  self.additionalProgressInverse = inverse;

  local effectiveInverse = (inverse and not self.inverseDirection) or (not inverse and self.inverseDirection);

  if (additionalProgress) then
    ensureExtraSpinners(self, #additionalProgress);
    local totalWidth = max - min;
    for index, additionalProgress in ipairs(additionalProgress) do
      local extraSpinner = self.extraSpinners[index];

      local startProgress, endProgress = convertToProgress(self.progress, additionalProgress, min,
                                                           totalWidth, effectiveInverse, self.overlayclip)
      if (endProgress < startProgress) then
        startProgress, endProgress = endProgress, startProgress;
      end

      if (self.orientation == "ANTICLOCKWISE") then
        startProgress, endProgress = 1 - endProgress, 1 - startProgress;
      end

      if ((endProgress - startProgress) == 0) then
        extraSpinner:SetProgress(0, 0)
      else
        local color = self.overlays[index];
        if (color) then
          extraSpinner:SetColor(unpack(color));
        else
          extraSpinner:SetColor(1, 1, 1, 1);
        end

        local startAngle = self.startAngle;
        local diffAngle = self.endAngle - startAngle;
        local pAngleStart = diffAngle * startProgress + startAngle;
        local pAngleEnd = diffAngle * endProgress + startAngle;

        if (pAngleStart < 0) then
          pAngleStart = pAngleStart + 360;
          pAngleEnd = pAngleEnd + 360;
        end

        extraSpinner:SetProgress(pAngleStart, pAngleEnd)
      end
    end

  else
    hideExtraTextures(self.extraSpinners, 1);
  end
end

local function FrameTick(self)
  local duration = self.duration
  local expirationTime = self.expirationTime
  local inverse = self.inverse

  local progress = 1;
  if (duration ~= 0) then
    local remaining = expirationTime - GetTime();
    progress = remaining / duration;
    local inversed = not inverse ~= not self.inverseDirection
    if(inversed) then
      progress = 1 - progress;
    end
  end

  progress = progress > 0.0001 and progress or 0.0001;

  if (self.useSmoothProgress) then
    self.smoothProgress:SetSmoothedValue(progress);
  else
    self:SetValueOnTexture(progress);
    self:ReapplyAdditionalProgress()
  end
end

local function CircularFrameTick(self)
  -- Native anchors normalize the source, including numeric inversion. The
  -- resulting fraction may be secret: only forward it to the native shader.
  self.secretTexture:SetRadialProgressBarPercent(self.secretFillFrame:GetWidth())
end

local function StopFrameTick(self)
  if self.FrameTick then
    self.FrameTick = nil
    self.subRegionEvents:RemoveSubscriber("FrameTick", self)
  end
end

local function ResetSecretBar(bar)
  -- SetValue detaches native timer updates, including when a pooled region is
  -- reused for an ordinary progress source.
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0, Enum.StatusBarInterpolation.Immediate)
  bar:Hide()
end

local whiteTexture = "Interface\\AddOns\\M33kAuras\\Media\\Textures\\Square_FullWhite"
-- The client rounds native fill anchors in logical UI units. An integer width
-- preserves empty/full endpoints; the readout frame converts it to a fraction.
-- 65536 (2^16) is our precision scale, not an API requirement: one driver unit
-- represents 1/65536 of the progress range. The readout uses the same scale.
local circularDriverWidth = 65536

local function SetSecretBarLinear(bar)
  bar:SetRenderMode(Enum.StatusBarRenderMode.Linear)
  local texture = bar:GetStatusBarTexture()
  texture:ClearRadialProgressBar()
  texture:SetSnapToPixelGrid(false)
  texture:SetTexture(whiteTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  texture:SetRotation(0)
  texture:SetTexCoord(0, 1, 0, 1)
  texture:SetBlendMode("BLEND")
  texture:SetDesaturated(false)
  bar:SetStatusBarColor(1, 1, 1, 0)
end

local function AnchorSecretFill(bar, fill, horizontal, reverse, inverse)
  local texture = bar:GetStatusBarTexture()
  bar:SetOrientation(horizontal and "HORIZONTAL" or "VERTICAL")
  bar:SetReverseFill(inverse and not reverse or (not inverse and reverse))
  fill:ClearAllPoints()
  if not inverse then
    fill:SetAllPoints(texture)
  elseif horizontal and not reverse then
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT")
    fill:SetPoint("BOTTOMRIGHT", texture, "BOTTOMLEFT")
  elseif horizontal then
    fill:SetPoint("TOPLEFT", texture, "TOPRIGHT")
    fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
  elseif not reverse then
    fill:SetPoint("TOPLEFT", texture, "BOTTOMLEFT")
    fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
  else
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT")
    fill:SetPoint("BOTTOMRIGHT", texture, "TOPRIGHT")
  end
end

local textureCorners = {
  {"UL", UPPER_LEFT_VERTEX, 0, 0}, {"LL", LOWER_LEFT_VERTEX, 0, 1},
  {"UR", UPPER_RIGHT_VERTEX, 1, 0}, {"LR", LOWER_RIGHT_VERTEX, 1, 1},
}

local centerRotationPoint = CreateVector2D(0.5, 0.5)
local topLeftRotationPoint = CreateVector2D(0, 0)
local bottomRightRotationPoint = CreateVector2D(1, 1)
local linearMaskPadding = 0.01

-- Warnings belong to an aura, while clones can use different progress sources.
local circularCropWarnings = setmetatable({}, {__mode = "k"})
local function UpdateCircularCropWarning(self, unsupported)
  local uid = self.secretProgressUid
  -- Collapse marks the region hidden before PreHide and condition resets.
  -- Pooled clones stay referenced, so weak keys alone cannot release owners.
  circularCropWarnings[self] = unsupported and self.toShow ~= false and uid or nil
  local affected = false
  for _, ownerUid in pairs(circularCropWarnings) do
    if ownerUid == uid then
      affected = true
      break
    end
  end
  Private.AuraWarnings.UpdateWarning(uid, "secretCircularCrop", affected and "warning" or nil,
    affected and L["Secret circular progress requires equal Crop X and Crop Y. The foreground is hidden until they match."] or nil)
end

local funcs = {
  PreShow = function(self)
    if self.secretCircularUnsupported then
      UpdateCircularCropWarning(self, true)
    end
    if self.secretProgress then
      self.secretBar:SetToTargetValue()
      if self.usesSlantExtension then self.secretAuxBar:SetToTargetValue() end
      if self.circular then
        self.secretTexture:SetRadialProgressBarPercent(self.secretFillFrame:GetWidth())
      end
    elseif self.useSmoothProgress then
      self.smoothProgress:ResetSmoothedValue()
    end
  end,
  PreHide = function(self)
    if self.secretCircularUnsupported then
      UpdateCircularCropWarning(self, false)
    end
  end,
  UseNormalProgress = function(self)
    if not self.secretBarMode then
      return
    end
    StopFrameTick(self)
    ResetSecretBar(self.secretBar)
    ResetSecretBar(self.secretAuxBar)
    self.secretTexture:ClearRadialProgressBar()
    self.secretBarMode = nil
    self.secretGeometryInverse = nil
    self.secretGeometryDirty = nil
    self.usesSlantExtension = nil
    self.secretTexture:Hide()
    self.secretMask:Hide()
    self.secretRotationAngle = nil
    self.secretRotationCircular = nil
    if self.secretCircularUnsupported then
      UpdateCircularCropWarning(self, false)
      self.secretCircularUnsupported = nil
    end
    -- Native appearance updates leave hidden ordinary textures untouched.
    -- Restore their current appearance once when returning to this renderer.
    local r, g = self.color_anim_r or self.color_r, self.color_anim_g or self.color_g
    local b, a = self.color_anim_b or self.color_b, self.color_anim_a or self.color_a
    self.foreground:SetColor(r, g, b, a)
    self.foregroundSpinner:SetColor(r, g, b, a)
    self.foreground:SetDesaturated(self.desaturateForeground)
    self.foregroundSpinner:SetDesaturated(self.desaturateForeground)
    if self.circular then
      self.foregroundSpinner:Show()
    else
      self.foreground:Show()
    end
  end,
  UpdateSecretColor = function(self)
    if self.secretProgress then
      self.secretTexture:SetVertexColor(self.color_anim_r or self.color_r, self.color_anim_g or self.color_g,
                                        self.color_anim_b or self.color_b, self.color_anim_a or self.color_a)
    end
  end,
  UpdateSecretTexture = function(self)
    if not self.secretProgress then
      return
    end
    local texture = self.secretTexture
    local wrap = self.circular and "CLAMPTOBLACKADDITIVE" or self.textureWrapMode
    Private.SetTextureOrAtlas(texture, self.currentTexture, wrap, wrap)
    texture:SetBlendMode(self.foreground:GetBlendMode())
    texture:SetDesaturated(self.desaturateForeground)
    self:UpdateSecretColor()
    self:UpdateSecretTexCoords()
    self:UpdateSecretRotation()
  end,
  UpdateSecretTexCoords = function(self)
    if not self.secretProgress then
      return
    end
    local texture, coord = self.secretTexture, self.secretTextureCoords
    local unsupported = self.circular and self.crop_x ~= self.crop_y
    if (self.secretCircularUnsupported or false) ~= unsupported then
      self.secretCircularUnsupported = unsupported
      UpdateCircularCropWarning(self, unsupported)
    end
    texture:SetShown(not unsupported and (self.circular or not self.hideLinearFill))
    coord:SetFull()
    if not self.circular and self.slanted and self.slantMode == "EXTEND" then
      local slant = self.slant or 0
      local horizontal = self.orientation == "HORIZONTAL" or self.orientation == "HORIZONTAL_INVERSE"
      for _, corner in ipairs(textureCorners) do
        local axis = corner[1] .. (horizontal and "x" or "y")
        coord[axis] = coord[axis] * (1 + 2 * slant) - slant
      end
    end
    local mirrorH = self.mirror_h or false
    if self.mirror then mirrorH = not mirrorH end
    local mirrorV = self.mirror_v or false
    local rotation = self.effectiveTexRotation or self.texRotation
    if self.circular then
      -- The radial shader shares the artwork's UVs. Keep them canonical and
      -- put the inverse artwork transform in public vertices instead. Equal
      -- crop preserves angular progress; the static mask clips to the region.
      local width, height = self.width * self.scalex, self.height * self.scaley
      local cosine, sine = cos(rotation), sin(rotation)
      local cropX = self.crop_x / 1.4142 * (mirrorH and -1 or 1)
      local cropY = self.crop_y / 1.4142 * (mirrorV and -1 or 1)
      for _, corner in ipairs(textureCorners) do
        local name, u, v = corner[1], corner[3] - 0.5, corner[4] - 0.5
        local x = (cosine * u + sine * v) * cropX
        local y = (-sine * u + cosine * v) * cropY
        coord[name .. "vx"] = (x - u) * width
        coord[name .. "vy"] = -(y - v) * height
      end
      local reverse = self.orientation == "ANTICLOCKWISE"
      local origin = reverse and self.endAngle or self.startAngle
      local reflected = mirrorH ~= mirrorV
      origin = rotation + (reflected and -origin or origin) + (mirrorV and 180 or 0)
      texture:SetRadialProgressBarStartOffset(((origin + 180) % 360) / 360)
      texture:SetRadialProgressBarEndOffset(1 - (self.endAngle - self.startAngle) / 360)
      texture:SetRadialProgressBarReverse(reverse ~= reflected)
      texture:SetRadialProgressBarFeather(0)
    else
      coord:Transform(self.crop_x, self.crop_y, rotation, mirrorH, mirrorV, self.user_x, self.user_y)
    end
    coord:Apply()
  end,
  UpdateSecretRotation = function(self, force)
    local angle = self.auraRotation or 0
    if not force and self.secretRotationAngle == angle and self.secretRotationCircular == self.circular then return end
    self.secretRotationAngle = angle
    self.secretRotationCircular = self.circular
    local radians = math.rad(angle)
    local rotationPoint = centerRotationPoint
    if not self.circular and not self.compress then
      -- The artwork rotates around the region center, but the mask's center
      -- moves with secret progress. Rotate around its fixed corner instead and
      -- translate both anchors by R(corner) - corner. Only public size/angle
      -- enter this calculation; the moving fill edge stays natively anchored.
      local horizontal = self.orientation == "HORIZONTAL" or self.orientation == "HORIZONTAL_INVERSE"
      local reverse = self.orientation == "HORIZONTAL_INVERSE" or self.orientation == "VERTICAL_INVERSE"
      local width, height = self.width * self.scalex, self.height * self.scaley
      local shift = self.slanted and self.slantMode == "EXTEND" and -(self.slant or 0) or 0
      local topLeft = horizontal and not reverse or not horizontal and reverse
      local x, y
      if topLeft then
        x = -width / 2 + (horizontal and shift * width or 0) - linearMaskPadding
        y = height / 2 - (not horizontal and shift * height or 0) + linearMaskPadding
        rotationPoint = topLeftRotationPoint
      else
        x = width / 2 - (horizontal and shift * width or 0)
        y = -height / 2 + (not horizontal and shift * height or 0)
        rotationPoint = bottomRightRotationPoint
      end
      local dx, dy = 0, 0
      if angle ~= 0 then
        local cosine, sine = cos(angle), sin(angle)
        dx, dy = cosine * x - sine * y - x, sine * x + cosine * y - y
      end
      self.secretMask:SetPoint("TOPLEFT", self.secretFillFrame, "TOPLEFT", dx - linearMaskPadding, dy + linearMaskPadding)
      self.secretMask:SetPoint("BOTTOMRIGHT", self.secretFillFrame, "BOTTOMRIGHT", dx, dy)
    end
    self.secretTexture:SetRotation(radians)
    self.secretMask:SetRotation(radians, rotationPoint)
  end,
  UpdateSecretGeometry = function(self)
    local bar, mask, fill = self.secretBar, self.secretMask, self.secretFillFrame
    -- Duration direction already includes both inversions. Numeric values need
    -- complementary geometry to invert the amount without Lua arithmetic.
    local inverse = self.secretProgress == "value" and self.inverseDirection
    self.usesSlantExtension = false
    if self.circular then
      bar:ClearAllPoints()
      bar:SetPoint("TOPLEFT", self, "TOPLEFT")
      bar:SetSize(circularDriverWidth, 1)
      fill:SetScale(circularDriverWidth)
      AnchorSecretFill(bar, fill, true, false, inverse)
      self.secretTextureFrame:ClearAllPoints()
      self.secretTextureFrame:SetAllPoints(self)
      self.secretTexture:ClearAllPoints()
      self.secretTexture:SetAllPoints(self.secretTextureFrame)
      mask:ClearAllPoints()
      mask:SetAllPoints(self.secretTextureFrame)
      for _, corner in ipairs(textureCorners) do
        mask:SetVertexOffset(corner[2], 0, 0)
      end
      mask:SetTexCoord(0, 1, 0, 1)
      return
    end

    fill:SetScale(1)
    local horizontal = self.orientation == "HORIZONTAL" or self.orientation == "HORIZONTAL_INVERSE"
    local reverse = self.orientation == "HORIZONTAL_INVERSE" or self.orientation == "VERTICAL_INVERSE"
    local width, height = self.width * self.scalex, self.height * self.scaley
    local slant = self.slanted and (self.slant or 0) or 0
    local extend = self.slantMode == "EXTEND"
    self.hideLinearFill = slant == 1 and not extend
    local factor = (not self.compress or extend) and (extend and 1 + slant or 1 - slant) or 1
    local shift = not self.compress and extend and -slant or 0
    local origin = horizontal and (reverse and "TOPRIGHT" or "TOPLEFT")
                             or (reverse and "TOPLEFT" or "BOTTOMLEFT")
    bar:ClearAllPoints()
    bar:SetPoint(origin, self, origin, horizontal and shift * width * (reverse and -1 or 1) or 0,
                                     not horizontal and shift * height * (reverse and -1 or 1) or 0)
    bar:SetSize(horizontal and width * factor or width, horizontal and height or height * factor)
    AnchorSecretFill(bar, fill, horizontal, reverse, inverse)
    self.secretTextureFrame:ClearAllPoints()
    self.secretTexture:ClearAllPoints()
    self.secretTexture:SetAllPoints(self.secretTextureFrame)
    self.secretTextureFrame:SetAllPoints(self)
    if not self.compress and extend and slant > 0 then
      -- EXTEND slants can draw outside the region. Expand the artwork as well
      -- as the mask; an enlarged mask cannot reveal pixels outside its texture.
      self.secretTexture:ClearAllPoints()
      self.secretTexture:SetPoint("TOPLEFT", self.secretTextureFrame, "TOPLEFT", horizontal and -slant * width or 0,
                                  horizontal and 0 or slant * height)
      self.secretTexture:SetPoint("BOTTOMRIGHT", self.secretTextureFrame, "BOTTOMRIGHT", horizontal and slant * width or 0,
                                  horizontal and 0 or -slant * height)
    end
    mask:ClearAllPoints()
    for _, corner in ipairs(textureCorners) do
      mask:SetVertexOffset(corner[2], 0, 0)
    end
    mask:SetTexCoord(0, 1, 0, 1)
    self.usesSlantExtension = self.compress and extend and slant > 0

    local shape = self.secretShape
    shape.width, shape.height = width, height
    shape.slant, shape.slantFirst, shape.slantMode = slant, self.slantFirst, self.slantMode
    shape.coord:SetFull()
    self.foreground.ApplyProgressToCoord(shape, 0, 1)
    local coord = shape.coord
    if self.compress then
      self.secretTextureFrame:ClearAllPoints()
      if self.usesSlantExtension then
        local extension, extensionFill = self.secretAuxBar, self.secretAuxFillFrame
        extension:ClearAllPoints()
        local point = horizontal and (reverse and "TOPLEFT" or "TOPRIGHT")
                                or (reverse and "BOTTOMLEFT" or "TOPLEFT")
        extension:SetPoint(point, self, origin)
        extension:SetSize(horizontal and width * slant or width, horizontal and height or height * slant)
        AnchorSecretFill(extension, extensionFill, horizontal, not reverse, inverse)
        local first = (horizontal and not reverse) or (not horizontal and reverse)
        self.secretTextureFrame:SetPoint("TOPLEFT", first and extensionFill or fill, "TOPLEFT")
        self.secretTextureFrame:SetPoint("BOTTOMRIGHT", first and fill or extensionFill, "BOTTOMRIGHT")
      else
        self.secretTextureFrame:SetAllPoints(fill)
      end
      mask:SetAllPoints(self.secretTextureFrame)
      -- A public shear in mask coordinates scales with the native rectangle.
      -- Unlike pixel vertex offsets, this also preserves slant under compression.
      local span = horizontal and coord.URx - coord.ULx or coord.LLy - coord.ULy
      if span == 0 then
        mask:SetTexCoord(-1, -1, -1, -1)
      else
        local coords = {}
        for _, corner in ipairs(textureCorners) do
          local u, v = corner[3], corner[4]
          if horizontal then
            local x = extend and u * (1 + 2 * slant) - slant or u
            u = (x - coord.ULx - (coord.LLx - coord.ULx) * v) / span
          else
            local y = extend and v * (1 + 2 * slant) - slant or v
            v = (y - coord.ULy - (coord.URy - coord.ULy) * u) / span
          end
          coords[#coords + 1], coords[#coords + 2] = u, v
        end
        mask:SetTexCoord(unpack(coords))
      end
    else
      local left = horizontal and (reverse and 1 - shift - factor or shift) or 0
      local top = not horizontal and (reverse and shift or 1 - shift - factor) or 0
      for _, corner in ipairs(textureCorners) do
        local name, vertex, x, y = unpack(corner)
        mask:SetVertexOffset(vertex, (coord[name .. "x"] - left - x * (horizontal and factor or 1)) * width,
                                     -(coord[name .. "y"] - top - y * (horizontal and 1 or factor)) * height)
      end
    end
  end,
  UpdateSecretBar = function(self)
    local mode = self.circular and "circular" or "linear"
    local inverse = self.secretProgress == "value" and self.inverseDirection or false
    local changedMode = self.secretBarMode ~= mode
    if not changedMode and self.secretGeometryInverse == inverse and not self.secretGeometryDirty then
      return false
    end
    local snapProgress = changedMode and self.secretBarMode ~= nil
    if changedMode then
      if not self.secretBarMode then
        -- First native entry: stop ordinary smoothing and hide its foregrounds.
        self.smoothProgress:ResetSmoothedValue()
        StopFrameTick(self)
        self.foreground:Hide()
        self.foregroundSpinner:Hide()
        self.additionalProgress = nil
        self.additionalProgressMin, self.additionalProgressMax = nil, nil
        hideExtraTextures(self.extraTextures, 1)
        hideExtraTextures(self.extraSpinners, 1)
      end
      -- The auxiliary only drives compressed slants. Discard its previous
      -- timer and interpolation before switching renderer roles.
      ResetSecretBar(self.secretBar)
      ResetSecretBar(self.secretAuxBar)
      self.secretBarMode = mode
    end
    self.secretGeometryInverse = inverse
    self.secretGeometryDirty = nil
    local wasExtension = self.usesSlantExtension
    if not self.circular then
      self.secretTexture:ClearRadialProgressBar()
    end
    self:UpdateSecretGeometry()
    self.secretMask:Show()
    if changedMode then
      self:UpdateSecretTexture()
    else
      self:UpdateSecretTexCoords()
      -- Size, direction, and compression can change the mask's fixed corner
      -- without changing the angle.
      self:UpdateSecretRotation(true)
    end
    self.secretBar:Show()
    if self.usesSlantExtension then
      self.secretAuxBar:Show()
    elseif wasExtension and not changedMode then
      ResetSecretBar(self.secretAuxBar)
    end
    if changedMode then
      if self.circular then
        -- RegionPrototype activates this subscription only while toShow is true,
        -- using the same lifecycle as ordinary timed progress.
        self.FrameTick = CircularFrameTick
        self.subRegionEvents:AddSubscriber("FrameTick", self)
      else
        StopFrameTick(self)
      end
    end
    return snapProgress or (self.usesSlantExtension and not wasExtension)
  end,
  SetProgressSecret = function(self)
    local snapProgress = self:UpdateSecretBar()
    local bar, auxiliary = self.secretBar, self.usesSlantExtension and self.secretAuxBar
    if self.secretProgress == "duration" then
      local inverse = not self.inverse ~= not self.inverseDirection
      local direction = inverse and Enum.StatusBarTimerDirection.ElapsedTime or Enum.StatusBarTimerDirection.RemainingTime
      bar:SetTimerDuration(self.durationObject, Enum.StatusBarInterpolation.Immediate, direction)
      if auxiliary then
        auxiliary:SetTimerDuration(self.durationObject, Enum.StatusBarInterpolation.Immediate, direction)
      end
    else
      local interpolation = self.useSmoothProgress and Enum.StatusBarInterpolation.ExponentialEaseOut
                                                    or Enum.StatusBarInterpolation.Immediate
      bar:SetMinMaxValues(self.minProgress, self.maxProgress)
      bar:SetValue(self.value, interpolation)
      if auxiliary then
        auxiliary:SetMinMaxValues(self.minProgress, self.maxProgress)
        auxiliary:SetValue(self.value, interpolation)
      end
    end
    if snapProgress then
      -- Start newly assigned drivers at their targets before interpolating later
      -- updates. EXTEND's two edges must also start with a shared value.
      bar:SetToTargetValue()
      if auxiliary then auxiliary:SetToTargetValue() end
    end
    if self.circular then
      self.secretTexture:SetRadialProgressBarPercent(self.secretFillFrame:GetWidth())
    end
  end,
  UpdateDuration = function(self)
    self.secretProgress = "duration"
    self:SetProgressSecret()
  end,
  ForAllSpinners = function(self, f, ...)
    f(self.foregroundSpinner, ...)
    f(self.backgroundSpinner, ...)
    for i, extraSpinner in ipairs(self.extraSpinners) do
      f(extraSpinner, ...)
    end
  end,
  ForAllLinears = function(self, f, ...)
    f(self.foreground, ...)
    f(self.background, ...)
    for _, extraTexture in ipairs(self.extraTextures) do
      f(extraTexture, ...)
    end
  end,
  SetOrientation = function (self, orientation)
    self.orientation = orientation
    if(self.orientation == "CLOCKWISE" or self.orientation == "ANTICLOCKWISE") then
      self.circular = true
      self.foreground:Hide()
      self.background:Hide()
      self.foregroundSpinner:Show()
      self.backgroundSpinner:Show()

      for i = 1, #self.extraTextures do
        self.extraTextures[i]:Hide()
      end
      self.foregroundSpinner:UpdateTextures()
      self.backgroundSpinner:UpdateTextures()
      self.SetValueOnTexture = CircularSetValueFunctions[self.orientation]
      self.ApplyAdditionalProgress = ApplyAdditionalProgressCircular
    else
      self.circular = false
      self.foreground:Show()
      self.background:Show()
      self.foregroundSpinner:Hide()
      self.backgroundSpinner:Hide()

      for i = 1, #self.extraSpinners do
        self.extraSpinners[i]:Hide()
      end
      self.background:SetOrientation(orientation, nil, self.slanted, self.slant,
                                       self.slantFirst, self.slantMode)
      self.foreground:SetOrientation(orientation, self.compress, self.slanted, self.slant,
                                       self.slantFirst, self.slantMode)
      self.SetValueOnTexture = TextureSetValueFunction;
      self.ApplyAdditionalProgress = ApplyAdditionalProgressLinear

      for _, extraTexture in ipairs(self.extraTextures) do
        extraTexture:SetOrientation(orientation, self.compress, self.slanted, self.slant,
                                    self.slantFirst, self.slantMode)
      end
    end
    if self.secretProgress then
      self.foreground:Hide()
      self.foregroundSpinner:Hide()
      self.secretGeometryDirty = true
      self:SetProgressSecret()
    else
      self:SetValueOnTexture(self.progress)
      self:ReapplyAdditionalProgress()
    end
  end,
  SetAnimRotation = function(self, angle)
    self.texAnimationRotation = angle
    self:UpdateEffectiveRotation()
  end,
  SetTexRotation = function(self, angle)
    self.texRotation = angle
    self:UpdateEffectiveRotation()
  end,
  GetBaseRotation = function(self)
    return self.texRotation
  end,
  Color = function(self, r, g, b, a)
    self.color_r = r
    self.color_g = g
    self.color_b = b
    if (r or g or b) then
      a = a or 1
    end
    self.color_a = a
    r, g, b, a = self.color_anim_r or r, self.color_anim_g or g, self.color_anim_b or b, self.color_anim_a or a
    if self.secretProgress then
      self.secretTexture:SetVertexColor(r, g, b, a)
    else
      self.foreground:SetColor(r, g, b, a)
      self.foregroundSpinner:SetColor(r, g, b, a)
    end
  end,
  ColorAnim = function(self, r, g, b, a)
    self.color_anim_r = r
    self.color_anim_g = g
    self.color_anim_b = b
    if (r or g or b) then
      a = a or 1;
    end
    self.color_anim_a = a
    r, g, b, a = r or self.color_r, g or self.color_g, b or self.color_b, a or self.color_a
    if self.secretProgress then
      self.secretTexture:SetVertexColor(r, g, b, a)
    else
      self.foreground:SetColor(r, g, b, a)
      self.foregroundSpinner:SetColor(r, g, b, a)
    end
  end,
  GetColor = function(self)
    return self.color_r, self.color_g, self.color_b, self.color_a
  end,
  SetAuraRotation = function(self, auraRotation)
    self.auraRotation = auraRotation
    local auraRotationRadians = self.auraRotation / 180 * math.pi
    self:ForAllSpinners(self.foregroundSpinner.SetAuraRotation, auraRotationRadians)

    self.background:SetAuraRotation(auraRotationRadians)
    self.foreground:SetAuraRotation(auraRotationRadians)
    for _, extraTexture in ipairs(self.extraTextures) do
      extraTexture:SetAuraRotation(auraRotationRadians)
    end
    if self.secretProgress then
      self:UpdateSecretRotation()
    end
  end,
  DoPosition = function(self)
    self:SetWidth(self.width * self.scalex);
    self:SetHeight(self.height * self.scaley);

    if self.orientation == "CLOCKWISE" or self.orientation == "ANTICLOCKWISE" then
      self:ForAllSpinners(self.foregroundSpinner.UpdateTextures)
    else
      self:ForAllLinears(self.foreground.Update)
    end
    if self.secretProgress then
      if self.circular then
        -- Circular anchors follow the region and the source width is fixed.
        self:UpdateSecretTexCoords()
      else
        self.secretGeometryDirty = true
        self:UpdateSecretBar()
      end
    end
  end,
  SetMirror = function(self, mirror)
    self.mirror = mirror
    self:ForAllSpinners(self.foregroundSpinner.SetMirror, mirror)
    self:ForAllLinears(self.foreground.SetMirror, mirror)
    self:UpdateSecretTexCoords()
  end,
  UpdateTextures = function(self)
    if self.circular then
      self:ForAllSpinners(self.foregroundSpinner.UpdateTextures)
    else
      self:ForAllLinears(self.foreground.UpdateTextures)
    end
    self:UpdateSecretTexCoords()
  end,
  SetCropX = function(self, x)
    self.crop_x = 1 + x
    self:ForAllSpinners(self.foregroundSpinner.SetCropX, self.crop_x)
    self:ForAllLinears(self.foreground.SetCropX, self.crop_x)
    self:UpdateSecretTexCoords()
  end,
  SetCropY = function(self, y)
    self.crop_y = 1 + y
    self:ForAllSpinners(self.foregroundSpinner.SetCropY, self.crop_y)
    self:ForAllLinears(self.foreground.SetCropY, self.crop_y)
    self:UpdateSecretTexCoords()
  end,
  UpdateEffectiveRotation = function(self)
    self.effectiveTexRotation = self.texAnimationRotation or self.texRotation
    self:ForAllSpinners(self.foregroundSpinner.SetTexRotation, self.effectiveTexRotation)
    self:ForAllLinears(self.foreground.SetTexRotation, self.effectiveTexRotation)
    self:UpdateSecretTexCoords()
  end,
  UpdateTime = function(self)
    self.secretProgress = nil
    if self.secretBarMode then self:UseNormalProgress() end
    local progress = 1
    if self.duration ~= 0 then
      local remaining = self.expirationTime - GetTime()
      progress = remaining / self.duration
      local inversed = not self.inverse ~= not self.inverseDirection
      if inversed then
        progress = 1 - progress
      end
    end

    progress = progress > 0.0001 and progress or 0.0001;
    if (self.useSmoothProgress) then
      self.smoothProgress:SetSmoothedValue(progress);
    else
      self:SetValueOnTexture(progress);
      self:ReapplyAdditionalProgress()
    end

    if self.paused and self.FrameTick then
      self.FrameTick = nil
      self.subRegionEvents:RemoveSubscriber("FrameTick", self)
    end
    if not self.paused and not self.FrameTick then
      self.FrameTick = FrameTick
      self.subRegionEvents:AddSubscriber("FrameTick", self)
    end
  end,
  UpdateValue = function(self)
    if hasanysecretvalues(self.value, self.total) then
      self.secretProgress = "value"
      self:SetProgressSecret()
      return
    end

    self.secretProgress = nil
    if self.secretBarMode then self:UseNormalProgress() end

    local progress = 1
    if(self.total > 0) then
      progress = self.value / self.total;
      if self.inverseDirection then
        progress = 1 - progress;
      end
    end
    progress = progress > 0.0001 and progress or 0.0001;
    if self.useSmoothProgress then
      self.smoothProgress:SetSmoothedValue(progress);
    else
      self:SetValueOnTexture(progress);
      self:ReapplyAdditionalProgress()
    end

    if self.FrameTick then
      self.FrameTick = nil
      self.subRegionEvents:RemoveSubscriber("FrameTick", self)
    end
  end,
  SetAdditionalProgress = function(self, additionalProgress, currentMin, currentMax, inverse)
    -- Texture overlays require arithmetic; only status bars can render secret progress.
    if self.secretProgress or hasanysecretvalues(self.progress, currentMin, currentMax)
      or (self.progressType == "static" and hasanysecretvalues(self.value, self.total))
    then
      additionalProgress, currentMin, currentMax = nil, nil, nil;
    end
    self:ApplyAdditionalProgress(additionalProgress, currentMin, currentMax, inverse)
  end,
  ReapplyAdditionalProgress = function(self)
    if self.secretProgress then
      self:SetAdditionalProgress(nil)
      return
    end
    self:ApplyAdditionalProgress(self.additionalProgress, self.additionalProgressMin,
                                 self.additionalProgressMax, self.additionalProgressInverse)
  end,
  Update = function(self)
    self:UpdateProgress()
    local state = self.state

    if state.texture then
      self:SetTexture(state.texture)
    end
  end,
  SetTexture = function(self, texture)
    self.currentTexture = texture
    self.foreground:SetTextureOrAtlas(texture, self.textureWrapMode)
    self.foregroundSpinner:SetTextureOrAtlas(texture);
    if self.sameTexture then
      self.background:SetTextureOrAtlas(texture, self.textureWrapMode)
      self.backgroundSpinner:SetTextureOrAtlas(texture);
    end

    for _, extraTexture in ipairs(self.extraTextures) do
      extraTexture:SetTextureOrAtlas(texture, self.textureWrapMode)
    end

    for _, extraSpinner in ipairs(self.extraSpinners) do
      extraSpinner:SetTextureOrAtlas(texture);
    end
    self:UpdateSecretTexture()
  end,
  SetForegroundDesaturated = function(self, b)
    self.desaturateForeground = b
    if self.secretProgress then
      self.secretTexture:SetDesaturated(b)
    else
      self.foreground:SetDesaturated(b)
      self.foregroundSpinner:SetDesaturated(b)
    end
  end,
  SetBackgroundDesaturated = function(self, b)
    self.background:SetDesaturated(b)
    self.backgroundSpinner:SetDesaturated(b)
  end,
  SetBackgroundColor = function(self, r, g, b, a)
    self.background:SetColor(r, g, b, a)
    self.backgroundSpinner:SetColor(r, g, b, a)
  end,
  SetRegionWidth = function(self, width)
    self.width = width;
    self:ForAllSpinners(self.foregroundSpinner.SetWidth, width)
    self:ForAllLinears(self.foreground.SetWidth, width)
    self:Scale(self.scalex, self.scaley)
  end,
  SetRegionHeight = function(self, height)
    self.height = height
    self:ForAllSpinners(self.foregroundSpinner.SetHeight, height)
    self:ForAllLinears(self.foreground.SetHeight, height)
    self:Scale(self.scalex, self.scaley)
  end,
  Scale = function(self, scalex, scaley)
    if(scalex < 0) then
      self.mirror_h = true
      scalex = scalex * -1
    end

    if(scaley < 0) then
      self.mirror_v = true
      scaley = scaley * -1
    end

    self.scalex = scalex
    self.scaley = scaley

    self:ForAllSpinners(self.foregroundSpinner.SetScale, self.scalex, self.scaley)
    self:ForAllSpinners(self.foregroundSpinner.SetMirrorHV, self.mirror_h, self.mirror_v)
    self:ForAllLinears(self.foreground.SetMirrorHV, self.mirror_h, self.mirror_v)
    self:DoPosition()
  end,
  SetInverse = function(self, inverse)
    if self.inverseDirection == inverse then
      return
    end
    self.inverseDirection = inverse
    if self.secretProgress then
      self.secretGeometryDirty = true
      self:SetProgressSecret()
      return
    end
    local progress = 1 - self.progress;
    progress = progress > 0.0001 and progress or 0.0001;
    self:SetValueOnTexture(progress)
    self:ReapplyAdditionalProgress()
  end,
  SetOverlayColor = function(self, id, r, g, b, a)
    self.overlays[id] = { r, g, b, a};
    if self.extraTextures[id] then
      self.extraTextures[id]:SetColor(r, g, b, a);
    end
    if self.extraSpinners[id] then
      self.extraSpinners[id]:SetColor(r, g, b, a);
    end
  end
}

local function create(parent)
  local region = CreateFrame("Frame", nil, parent);
  region.regionType = "progresstexture"
  region:SetMovable(true);
  region:SetResizable(true);
  region:SetResizeBounds(1, 1)

  local background = Private.LinearProgressTextureBase.create(region, "BACKGROUND", 0);
  region.background = background;

  -- For horizontal/vertical progress
  local foreground = Private.LinearProgressTextureBase.create(region, "ARTWORK", 0);
  region.foreground = foreground;

  region.foregroundSpinner = Private.CircularProgressTextureBase.create(region, "ARTWORK", 1)
  region.backgroundSpinner = Private.CircularProgressTextureBase.create(region, "BACKGROUND", 1)

  local secretBar = CreateFrame("StatusBar", nil, region)
  secretBar:SetStatusBarTexture(whiteTexture)
  local barTexture = secretBar:GetStatusBarTexture()
  barTexture:SetDrawLayer("ARTWORK", 0)
  barTexture:SetTexelSnappingBias(0)
  SetSecretBarLinear(secretBar)
  secretBar:Hide()
  region.secretBar = secretBar
  region.secretFillFrame = CreateFrame("Frame", nil, region)
  -- A second linear driver supplies the opposite edge of compressed EXTEND.
  local auxiliary = CreateFrame("StatusBar", nil, region)
  auxiliary:SetStatusBarTexture(whiteTexture)
  SetSecretBarLinear(auxiliary)
  auxiliary:Hide()
  region.secretAuxBar = auxiliary
  region.secretAuxFillFrame = CreateFrame("Frame", nil, region)

  local secretTextureFrame = CreateFrame("Frame", nil, region)
  secretTextureFrame:SetAllPoints(region)
  local secretTexture = secretTextureFrame:CreateTexture(nil, "ARTWORK", nil, 0)
  secretTexture:SetAllPoints(secretTextureFrame)
  secretTexture:SetSnapToPixelGrid(false)
  secretTexture:SetTexelSnappingBias(0)
  secretTexture:Hide()
  region.secretTextureFrame = secretTextureFrame
  region.secretTexture = secretTexture
  region.secretTextureCoords = Private.TextureCoords.create(secretTexture)
  local mask = secretTextureFrame:CreateMaskTexture()
  mask:SetTexture(whiteTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
  mask:SetSnapToPixelGrid(false)
  mask:SetTexelSnappingBias(0)
  secretTexture:AddMaskTexture(mask)
  mask:Hide()
  region.secretMask = mask
  region.secretShape = {coord = Private.TextureCoords.create(mask)}
  -- Subregion frames start one level above the region. Native foregrounds must
  -- remain beneath them when groups change the region's frame level.
  local function UpdateSecretFrameLevel()
    secretTextureFrame:SetFrameLevel(region:GetFrameLevel())
    secretBar:SetFrameLevel(region:GetFrameLevel())
  end
  hooksecurefunc(region, "SetFrameLevel", UpdateSecretFrameLevel)
  UpdateSecretFrameLevel()

  region.extraTextures = {};
  region.extraSpinners = {};

  -- Use a dummy object for the SmoothStatusBarMixin, because our SetValue
  -- is used for a different purpose
  region.smoothProgress = {};
  Mixin(region.smoothProgress, Private.SmoothStatusBarMixin);
  region.smoothProgress.SetValue = function(self, progress)
    region:SetValueOnTexture(progress);
    region:ReapplyAdditionalProgress()
  end

  region.smoothProgress.GetValue = function(self)
    return region.progress;
  end

  region.smoothProgress.GetMinMaxValues = function(self)
    return 0, 1;
  end

  for k, func in pairs(funcs) do
    region[k] = func
  end

  Private.regionPrototype.create(region);

  return region;
end


local function modify(parent, region, data)
  region.secretProgress = nil
  region:UseNormalProgress()
  region.secretProgressUid = data.uid
  region.smoothProgress:ResetSmoothedValue()
  StopFrameTick(region)
  Private.regionPrototype.modify(parent, region, data);

  local background, foreground = region.background, region.foreground;
  local foregroundSpinner, backgroundSpinner = region.foregroundSpinner, region.backgroundSpinner;

  background:Hide()
  foreground:Hide()
  foregroundSpinner:Hide()
  backgroundSpinner:Hide()

  region:SetWidth(data.width);
  region:SetHeight(data.height);
  region.width = data.width;
  region.height = data.height;
  region.scalex = 1;
  region.scaley = 1;
  region.aspect =  data.width / data.height;
  region.overlayclip = data.overlayclip;

  region.textureWrapMode = data.textureWrapMode;
  region.useSmoothProgress = data.smoothProgress
  region.sameTexture = data.sameTexture
  region.mirror = data.mirror
  region.crop_x = 1 + data.crop_x
  region.crop_y = 1 + data.crop_y
  region.texRotation = data.rotation or 0
  region.user_x = -1 * (data.user_x or 0);
  region.user_y = data.user_y or 0;
  region.startAngle = (data.startAngle or 0) % 360;
  region.endAngle = (data.endAngle or 360) % 360;
  if (region.endAngle <= region.startAngle) then
    region.endAngle = region.endAngle + 360;
  end
  region.compress = data.compress;
  region.inverseDirection = data.inverse;
  region.progress = 0.667;
  if (data.overlays) then
    region.overlays = CopyTable(data.overlays)
  else
    region.overlays = {}
  end
  region.slanted = data.slanted;
  region.slant = data.slant;
  region.slantFirst = data.slantFirst;
  region.slantMode = data.slantMode;
  region.auraRotation = data.auraRotation
  region.texRotation = data.rotation
  region.effectiveTexRotation = data.rotation
  region.desaturateForeground = data.desaturateForeground

  region.FrameTick = nil

  local auraRotationRadians = region.auraRotation / 180 * math.pi

  region.currentTexture = data.foregroundTexture

  Private.LinearProgressTextureBase.modify(region.background, {
    offset = data.backgroundOffset,
    texture = data.sameTexture and data.foregroundTexture or data.backgroundTexture,
    textureWrapMode = region.textureWrapMode,
    desaturated = data.desaturateBackground,
    blendMode = data.blendMode,
    auraRotation = auraRotationRadians,
    crop_x = region.crop_x,
    crop_y = region.crop_y,
    user_x = region.user_x,
    user_y = region.user_y,
    mirror = region.mirror,
    texRotation = region.texRotation,
    width = data.width,
    height = data.height
  })

  background:SetColor(data.backgroundColor[1], data.backgroundColor[2],
                      data.backgroundColor[3], data.backgroundColor[4])

  Private.LinearProgressTextureBase.modify(region.foreground, {
    offset = 0,
    texture = data.foregroundTexture,
    textureWrapMode = region.textureWrapMode,
    desaturated = data.desaturateForeground,
    blendMode = data.blendMode,
    auraRotation = auraRotationRadians,
    crop_x = region.crop_x,
    crop_y = region.crop_y,
    user_x = region.user_x,
    user_y = region.user_y,
    mirror = region.mirror,
    texRotation = region.texRotation,
    width = data.width,
    height = data.height
  })

  --- @type LinearProgressTextureOptions
  local linearOptions = {
    offset = 0,
    texture = data.foregroundTexture,
    textureWrapMode = region.textureWrapMode,
    desaturated = false,
    blendMode = data.blendMode,
    auraRotation = auraRotationRadians,
    crop_x = region.crop_x,
    crop_y = region.crop_y,
    user_x = region.user_x,
    user_y = region.user_y,
    mirror = region.mirror,
    texRotation = region.texRotation,
    width = data.width,
    height = data.height
  }
  for _, extraTexture in ipairs(region.extraTextures) do
    Private.LinearProgressTextureBase.modify(extraTexture, linearOptions)
  end

  Private.CircularProgressTextureBase.modify(region.foregroundSpinner, {
    crop_x = region.crop_x,
    crop_y = region.crop_y,
    mirror = data.mirror,
    texRotation = region.texRotation,
    texture = data.foregroundTexture,
    blendMode = data.blendMode,
    desaturated = data.desaturateForeground,
    auraRotation = auraRotationRadians,
    width = data.width,
    height = data.height,
    offset = 0
  })

  Private.CircularProgressTextureBase.modify(region.backgroundSpinner, {
    crop_x = region.crop_x,
    crop_y = region.crop_y,
    mirror = data.mirror,
    texRotation = region.texRotation,
    texture = data.sameTexture and data.foregroundTexture or data.backgroundTexture,
    blendMode = data.blendMode,
    desaturated = data.desaturateBackground,
    auraRotation = auraRotationRadians,
    width = data.width,
    height = data.height,
    offset = data.backgroundOffset
  })

  backgroundSpinner:SetColor(data.backgroundColor[1], data.backgroundColor[2],
                          data.backgroundColor[3], data.backgroundColor[4])
  backgroundSpinner:SetProgress(region.startAngle, region.endAngle)

  --- @type CircularProgressTextureOptions
  local spinnerOptions = {
    crop_x = region.crop_x,
    crop_y = region.crop_y,
    mirror = data.mirror,
    texRotation = region.texRotation,
    texture = data.foregroundTexture,
    blendMode = data.blendMode,
    desaturated = false,
    auraRotation = auraRotationRadians,
    width = data.width,
    height = data.height,
    offset = 0
  }
  for _, extraSpinner in ipairs(region.extraSpinners) do
    Private.CircularProgressTextureBase.modify(extraSpinner, spinnerOptions)
  end

  region:SetOrientation(data.orientation);
  region:DoPosition(region)
  region:Color(data.foregroundColor[1], data.foregroundColor[2], data.foregroundColor[3], data.foregroundColor[4]);

  Private.regionPrototype.modifyFinish(parent, region, data);
end

local function validate(data)
  Private.EnforceSubregionExists(data, "subbackground")
end

Private.RegisterRegionType("progresstexture", create, modify, default, GetProperties, validate);
