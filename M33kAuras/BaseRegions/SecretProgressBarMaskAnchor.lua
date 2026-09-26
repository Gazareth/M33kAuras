if not M33kAuras.IsLibsOK() then return end
---@type string
local AddonName = ...
---@class Private
local Private = select(2, ...)

--[[
  SecretProgressBarMaskAnchor

  This class abstracts the complex masking logic required to display "secret" (encrypted/protected)
  progress values in M33kAuras. Because the WoW Lua API restricts arithmetic on secret values,
  standard region textures cannot perform coordinate math to crop themselves.
  Instead, this controller creates a native, invisible WoW StatusBar (which securely handles secret math
  on the C-side) and anchors a mask to it. This mask is then applied to the region's foreground texture,
  seamlessly cropping it without relying on any forbidden math.
]]

local ORIENTATION_MAP = {
  HORIZONTAL         = { orientation = "HORIZONTAL", reverse = false },
  HORIZONTAL_INVERSE = { orientation = "HORIZONTAL", reverse = true },
  VERTICAL           = { orientation = "VERTICAL",   reverse = true },
  VERTICAL_INVERSE   = { orientation = "VERTICAL",   reverse = false },
}

local INVERSE_ORIENTATION_CONFIG = {
  HORIZONTAL = {
    p1 = "BOTTOMRIGHT", t1 = "texture", rp1 = "BOTTOMLEFT", x1 = 0, y1 = 0,
    p2 = "TOPLEFT", t2 = "region", rp2 = "TOPLEFT", x2 = -1, y2 = 1,
    reverseFill = true
  },
  HORIZONTAL_INVERSE = {
    p1 = "TOPLEFT", t1 = "texture", rp1 = "TOPRIGHT", x1 = -1, y1 = 1,
    p2 = "BOTTOMRIGHT", t2 = "region", rp2 = "BOTTOMRIGHT", x2 = 0, y2 = 0,
    reverseFill = false
  },
  VERTICAL = {
    p1 = "BOTTOMRIGHT", t1 = "texture", rp1 = "BOTTOMLEFT", x1 = 0, y1 = 0,
    p2 = "TOPLEFT", t2 = "region", rp2 = "TOPLEFT", x2 = -1, y2 = 1,
    reverseFill = true
  },
  VERTICAL_INVERSE = {
    p1 = "TOPLEFT", t1 = "texture", rp1 = "TOPLEFT", x1 = -1, y1 = 1,
    p2 = "BOTTOMRIGHT", t2 = "region", rp2 = "BOTTOMRIGHT", x2 = 0, y2 = 0,
    reverseFill = false
  }
}

local SecretProgressBarMaskAnchor = {}
Private.SecretProgressBarMaskAnchor = SecretProgressBarMaskAnchor
SecretProgressBarMaskAnchor.__index = SecretProgressBarMaskAnchor

function SecretProgressBarMaskAnchor.create(region)
  local self = setmetatable({}, SecretProgressBarMaskAnchor)
  self.region = region
  self.bar = CreateFrame("StatusBar", nil, region)
  self.bar:SetAllPoints(region)
  self.bar:SetStatusBarTexture("Interface\\AddOns\\M33kAuras\\Media\\Textures\\Square_FullWhite")
  self.bar:SetColorFill(1, 1, 1, 0)

  self.mask = region:CreateMaskTexture()
  self.mask:SetTexture("Interface\\AddOns\\M33kAuras\\Media\\Textures\\Square_FullWhite", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
  self.mask:SetTexelSnappingBias(0)
  self.mask:SetSnapToPixelGrid(false)

  self.active = false
  return self
end

function SecretProgressBarMaskAnchor:SetOrientation(orientation)
  local config = ORIENTATION_MAP[orientation]
  if config then
    self.bar:SetOrientation(config.orientation)
    self.bar:SetReverseFill(config.reverse)
  end
end

function SecretProgressBarMaskAnchor:UpdateInverse(effectiveOrientation, inverseDirection, force)
  local effectiveInverse = inverseDirection and effectiveOrientation or false
  if self.lastInverse == effectiveInverse and not force then
    return
  end
  self.lastInverse = effectiveInverse

  local OFFSET = 0.01
  self.mask:ClearAllPoints()
  local texture = self.bar:GetStatusBarTexture()

  if not inverseDirection then
    self.mask:SetPoint("TOPLEFT", texture, "TOPLEFT", -OFFSET, OFFSET)
    self.mask:SetPoint("BOTTOMRIGHT", texture, "BOTTOMRIGHT")
  else
    local cfg = INVERSE_ORIENTATION_CONFIG[effectiveInverse]
    if cfg then
      local target1 = (cfg.t1 == "texture") and texture or self.region
      self.mask:SetPoint(cfg.p1, target1, cfg.rp1, cfg.x1 * OFFSET, cfg.y1 * OFFSET)
      
      local target2 = (cfg.t2 == "texture") and texture or self.region
      self.mask:SetPoint(cfg.p2, target2, cfg.rp2, cfg.x2 * OFFSET, cfg.y2 * OFFSET)

      self.bar:SetReverseFill(cfg.reverseFill)
    end
  end
end

function SecretProgressBarMaskAnchor:Apply(textureObject)
  if self.active then return end
  if textureObject and textureObject.texture then
    textureObject.texture:AddMaskTexture(self.mask)
  end
  self.active = true
end

function SecretProgressBarMaskAnchor:Remove(textureObject)
  if not self.active then return end
  if textureObject and textureObject.texture then
    textureObject.texture:RemoveMaskTexture(self.mask)
  end
  self.active = false
end

function SecretProgressBarMaskAnchor:SetValues(value, minProgress, maxProgress, useSmoothProgress)
  self.bar:SetMinMaxValues(minProgress or 0, maxProgress or 1)
  if useSmoothProgress then
    self.bar:SetValue(value, Enum.StatusBarInterpolation.ExponentialEaseOut)
  else
    self.bar:SetValue(value)
  end
end
