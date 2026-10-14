-- STAR WARS Galactic Racer - VR cockpit package for UEVR (one file)
--
-- Credits: joeyhodge - the UEVR backend for this game; elliotttate & madscy - the VR cockpit
-- (v1.2.0, the cockpit section of this file), used and shared with their permission; Nero - the
-- profile and user_script tuning. v2.0.0 by ody: cockpit shake, boost effects, race start,
-- per-vehicle settings, menu. https://github.com/unuruu5760/SWGR-VR-Cockpit
--
-- Install: put this file in the UEVR profile's "scripts" folder (remove older swgr_cockpit_*.lua
-- scripts). Settings: UEVR menu > Script UI. Saved in the profile's "data" folder:
-- swgr_vr_settings.json, swgr_vr_vehicles.json, swgr_vr_views.json.
local LANG = '@LANG@'                      -- 'ko' / 'en' (set by the build)
local VERSION = '@VERSION@'
local api, callbacks = uevr.api, uevr.sdk.callbacks
local V = {}
SWGR_VR = V
