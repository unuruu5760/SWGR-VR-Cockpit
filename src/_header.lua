-- STAR WARS Galactic Racer - VR cockpit package for UEVR (one file)
--
-- Built on the UEVR profile and VR cockpit (v1.2.0, the cockpit section of this file) by Nero,
-- madscy and elliotttate, running on joeyhodge's UEVR backend for this game. v2.0.0 by ody: cockpit shake, boost effects, race start, per-vehicle
-- settings, menu. https://github.com/unuruu5760/SWGR-VR-Cockpit
--
-- Install: put this file in the UEVR profile's "scripts" folder (remove older swgr_cockpit_*.lua
-- scripts). Settings: UEVR menu > Script UI. Saved in the profile's "data" folder:
-- swgr_vr_settings.json, swgr_vr_vehicles.json, swgr_vr_views.json.
local LANG = '@LANG@'                      -- 'ko' / 'en' (set by the build)
local VERSION = '@VERSION@'
local PIC_LAB = @PIC_LAB@                  -- picture options still being worked on: on in the working build only
local api, callbacks = uevr.api, uevr.sdk.callbacks
local V = {}
SWGR_VR = V
