"""Upgrading must never lose what players saved. For every released version (git tags v*, without
-ko, of the repository): build it, let it save settings and per-vehicle values for plain and mixed
vehicles (parts of several models), then load those files with the new script and drive the same
vehicles. Every value must be what it was, and nothing may be removed from the files.
usage: python tools/luacheck/upgrade_test.py <new script.lua> <repository folder>
Exit code 1 if anything failed."""
import ctypes, json, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
L = ctypes.CDLL(os.path.join(HERE, 'lua51.dll'))
L.luaL_newstate.restype = ctypes.c_void_p
L.luaL_openlibs.argtypes = [ctypes.c_void_p]
L.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
L.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
L.lua_tolstring.restype = ctypes.c_char_p
L.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
L.lua_settop.argtypes = [ctypes.c_void_p, ctypes.c_int]
L.lua_close.argtypes = [ctypes.c_void_p]


def run(st, code, name):
    b = code.encode('utf-8')
    if L.luaL_loadbuffer(st, b, len(b), ('=' + name).encode()) != 0 or L.lua_pcall(st, 0, 1, 0) != 0:
        msg = L.lua_tolstring(st, -1, None).decode('utf-8', 'replace'); L.lua_settop(st, 0)
        raise RuntimeError('%s: %s' % (name, msg))
    r = L.lua_tolstring(st, -1, None); L.lua_settop(st, 0)
    return r.decode('utf-8') if r else ''


def lua_lit(v):
    if isinstance(v, bool): return 'true' if v else 'false'
    if v is None: return 'nil'
    if isinstance(v, (int, float)): return repr(v)
    if isinstance(v, str): return json.dumps(v)
    if isinstance(v, list): return '{' + ', '.join(lua_lit(x) for x in v) + '}'
    return '{' + ', '.join('[' + json.dumps(str(k)) + '] = ' + lua_lit(x) for k, x in v.items()) + '}'


# the vehicles driven in both versions: plain ones and mixed ones (the old name = most meshes)
VEHICLES = r'''
local FOLDER = { Bike = 'Bikes', Car = 'Cars', Skimmer = 'Skimmers', Plane = 'Planes' }
local BUILDS = {
    { tag = 'plain bike', ty = 'Bike', model = 'Taipan', recipe = 'Taipan', parts = { Front = 'Taipan', Rear = 'Taipan', Wings = 'Taipan' } },
    { tag = 'mixed bike', ty = 'Bike', model = 'Taipan', recipe = 'Taipan', parts = { Front = 'Taipan', Rear = 'Lancehead', Wings = 'Lancehead', Controls = 'Lancehead' } },
    { tag = 'mixed car', ty = 'Car', model = 'Goblin', recipe = 'Goblin FE Plus', parts = { Front = 'Goblin', Rear = 'Mako', FrontL = 'Orca', FrontR = 'Orca', EngineL = 'Orca' } },
    { tag = 'mixed podracer', ty = 'Plane', model = 'Myth', recipe = 'MythP2', parts = { Root = 'Myth', EngineL = 'Sordes', EngineR = 'Sordes', FrontL = 'Sordes' } },
}
local raceNo = 0
local function spawn(b)
    raceNo = raceNo + 1
    local pawn = MOCK.makeVehicle(b.ty, b.ty)       -- (the seat on a root every model shares)
    local extra, parts = {}, {}
    for slot, m in pairs(b.parts) do
        for i = 1, 3 do
            local n = 'SM_'..m..slot..'_Panel'..i
            local path = 'StaticMesh /Game/Griffin/Vehicles/'..FOLDER[b.ty]..'/Customisation/'..m..'/'..slot..'/'..n..'.'..n
            extra[#extra + 1] = { StaticMesh = { get_full_name = function() return path end, Sockets = {} }, SkeletalMesh = false }
        end
        parts[#parts + 1] = { PartType = slot, vehicleKit = m, ParentIndex = 0 }
    end
    if MOCK.newMock and MOCK.custom then             -- (older mocks have no recipe; older scripts don't read it)
        MOCK.custom.ActiveRecipe = { RecipeName = b.recipe, UnitRecipes = { { UnitName = 'Main', Parts = parts } } }
    end
    local orig, id = pawn.K2_GetComponentsByClass, 'pawn_up'..raceNo
    pawn.get_address = function() return id end
    pawn.K2_GetComponentsByClass = function(self, c)
        local r = orig(self, c)
        if not c.name:find('StaticMeshComponent', 1, true) then return r end
        local t = {}
        for _, x in ipairs(r) do t[#t + 1] = x end
        for _, x in ipairs(extra) do t[#t + 1] = x end
        return t
    end
    MOCK.pawn = pawn
    for i = 1, 50 do MOCK.frame(0.1) end
end
local function leave() MOCK.pawn = nil; for i = 1, 3 do MOCK.frame(0.1) end end
local V = SWGR_VR
local KEYS = { 'rollAmount', 'rollMax', 'near', 'springHz', 'ramjet', 'followUp' }
local GROUPS = { 'engine', 'road', 'roll' }
-- what a player gets on that vehicle now
local function snapshot(b)
    local m = V.model
    local e = m and (V.eyeFor and V.eyeFor(m)) or nil
    local s = { name = tostring(m), eye = e and string.format('%.2f/%.2f/%.2f', e[1], e[2], e[3]) or '-' }
    for _, k in ipairs(KEYS) do s[k] = m and string.format('%.3f', V.valFor(m, k)) or '-' end
    for _, g in ipairs(GROUPS) do
        local own = m and V.ownVal('feel', m, g)
        s['feel.'..g] = own and string.format('%.1f', own) or 'shared'
    end
    return s
end
local function enc(v)
    if type(v) == 'table' then
        local n, arr = 0, true
        for k in pairs(v) do n = n + 1; if type(k) ~= 'number' then arr = false end end
        local parts = {}
        if arr and n > 0 then for i = 1, n do parts[#parts + 1] = enc(v[i]) end; return '['..table.concat(parts, ',')..']' end
        for k, x in pairs(v) do if type(x) ~= 'function' then parts[#parts + 1] = string.format('%q', tostring(k))..':'..enc(x) end end
        return '{'..table.concat(parts, ',')..'}'
    elseif type(v) == 'string' then return string.format('%q', v)
    elseif type(v) == 'number' then return string.format('%.17g', v)
    elseif type(v) == 'boolean' then return tostring(v) end
    return 'null'
end
'''

OLD_SESSION = VEHICLES + r'''
-- shared settings a player changed
V.cfg.engine = 130; V.cfg.screen = 40; V.cfg.headHit = false; V.cfg.keyToggle = 'F6'
V.cfg.detail.springHz = 3.1
local snaps = {}
for i, b in ipairs(BUILDS) do
    spawn(b)
    local m = V.model
    V.setOwnVal('detail', m, 'rollAmount', 0.4 + i / 10)
    V.setOwnVal('detail', m, 'near', 10 + i)
    V.setOwnVal('feel', m, 'engine', 100 + i * 10)
    V.veh.eyes[m] = { i, -10 - i, 70 + i }
    V.saveVeh(); for k = 1, 10 do MOCK.frame(0.1) end
    snaps[i] = snapshot(b)
    leave()
end
-- picture values for whole maps (2.1.0: per map): a map with races, a paddock
if V.setPicVal then
    V.setPicVal('L_Mastiff_LOOP_B', 'picCon', 112); V.setPicVal('L_Mastiff_LOOP_B', 'picExp', -0.3)
    V.setPicVal('L_Mastiff_Paddock', 'picExp', -0.5)
end
V.saveNow(); V.saveVehNow()
return enc({ files = MOCK.files, snaps = snaps })
'''

NEW_SESSION = VEHICLES + r'''
-- first race of each build after the upgrade (older names are put right then), and the next one:
-- every build must have what it had in the older version, from the start
for i, b in ipairs(BUILDS) do spawn(b); leave() end
local snaps = {}
for i, b in ipairs(BUILDS) do spawn(b); snaps[i] = snapshot(b); leave() end
for k = 1, 10 do MOCK.frame(0.1) end
-- a race on the map with older picture values (they go to that race), then its paddock
local pic = {}
MOCK.world, MOCK.trackDef, MOCK.condition = 'L_Mastiff_LOOP_B', 'TRAK_MAS_LOOP_B_FWD', 'TrackCondition.Sunset'
for k = 1, 40 do MOCK.frame(0.1) end
pic.race = { place = tostring(V.picPlace()), picCon = V.picVal('picCon'), picExp = V.picVal('picExp') }
MOCK.world = 'L_Mastiff_Paddock'
for k = 1, 20 do MOCK.frame(0.1) end
pic.paddock = { place = tostring(V.picPlace()), picExp = V.picVal('picExp') }
MOCK.world = nil
for k = 1, 20 do MOCK.frame(0.1) end
V.saveNow(); V.saveVehNow()
return enc({ files = MOCK.files, snaps = snaps, pic = pic, errors = MOCK.errors })
'''


def session(script, mock, files, body, new):
    st = L.luaL_newstate(); L.luaL_openlibs(st)
    try:
        run(st, open(mock, encoding='utf-8').read(), 'mock')
        run(st, 'MOCK.newMock = ' + ('true' if new else 'false') + '\nMOCK.files = ' + lua_lit(files) + '\nMOCK.setWidthApi("next")\nreturn ""', 'files')
        run(st, open(script, encoding='utf-8').read(), os.path.basename(script))
        return json.loads(run(st, body, 'session'))
    finally:
        L.lua_close(st)


def missing(old, new, path=''):
    """values in old that new no longer has (or changed)"""
    out = []
    if isinstance(old, dict):
        if not isinstance(new, dict):
            return [path + ' (gone)']
        for k, v in old.items():
            out += missing(v, new.get(k), path + '.' + str(k))
    elif isinstance(old, list):
        if not isinstance(new, list) or len(new) != len(old):
            return [path + ' (changed)']
        for i, v in enumerate(old):
            out += missing(v, new[i], path + '[%d]' % i)
    else:
        if new is None:
            return [path + ' (gone)']
        if isinstance(old, (int, float)) and isinstance(new, (int, float)):
            if abs(old - new) > 1e-6:
                out.append('%s %s -> %s' % (path, old, new))
        elif old != new:
            out.append('%s %s -> %s' % (path, old, new))
    return out


# settings older versions kept and 2.1.1 carries over into today's keys (then drops)
OBSOLETE = {'shakeSaved', 'shakeDefault', 'shakeMasterByType', 'shakeAlongPerVehicle', 'landSlamV2', 'shakeAlong',
            'shakeAlongAir', 'shakeAlongSmooth', 'shakeAlongSmooth2', 'shakeAlongMove', 'shakeAlongLand', 'blockCamButton'}


def build_old(repo, tag, work):
    d = os.path.join(work, tag)
    os.makedirs(d)
    data = subprocess.run(['git', '-C', repo, 'archive', tag], capture_output=True, check=True).stdout
    p = os.path.join(work, tag + '.tar')
    open(p, 'wb').write(data)
    subprocess.run(['tar', '-xf', p, '-C', d], check=True)
    subprocess.run([sys.executable, os.path.join(d, 'build.py')], cwd=d, capture_output=True, check=True)
    return os.path.join(d, 'dist', 'EN', 'swgr_vr_cockpit.lua'), os.path.join(d, 'tests', 'mock.lua')


def main():
    new_script, repo = sys.argv[1], sys.argv[2]
    tags = subprocess.run(['git', '-C', repo, 'tag', '--list', 'v*'], capture_output=True, text=True, check=True).stdout.split()
    tags = sorted(t for t in tags if not t.endswith('-ko'))
    work = tempfile.mkdtemp(prefix='swgr_upgrade_')
    bad = 0
    try:
        for tag in tags:
            old_script, old_mock = build_old(repo, tag, work)
            old = session(old_script, old_mock, {}, OLD_SESSION, False)
            files = {k: v for k, v in old['files'].items() if k.endswith('.json')}
            new = session(new_script, os.path.join(HERE, 'mock.lua'), files, NEW_SESSION, True)
            problems = []
            # Nothing may vanish from the files, except: a format number going up, the settings older
            # versions kept and this one carries over (OBSOLETE), and older vehicle names put right ('moved':
            # their values are checked below, on the vehicle they belong to, and their backup is kept)
            moved = (new['files'].get('swgr_vr_vehicles.json') or {}).get('moved') or {}
            for f, content in files.items():
                for m in missing(content, new['files'].get(f, {})):
                    parts = m.split()[0].split('.')
                    if m.startswith('.format ') and float(m.split()[1]) < float(m.split()[3]): continue
                    if f == 'swgr_vr_settings.json' and len(parts) > 1 and parts[1] in OBSOLETE: continue
                    if f == 'swgr_vr_vehicles.json' and len(parts) > 2 and parts[1] in ('eyes', 'feel', 'detail', 'pilotFollow'):
                        name = parts[2] + '/' + parts[3] if len(parts) > 3 and parts[2] in ('Bike', 'Car', 'Skimmer', 'Plane') else parts[2]
                        name = name.split('[')[0]
                        kept = moved.get(name)
                        if isinstance(kept, dict) and not missing(content.get(parts[1], {}).get(name), kept.get(parts[1])):
                            continue          # (put right: what it had waits aside, unchanged)
                    if f == 'swgr_vr_vehicles.json' and len(parts) > 2 and parts[1] == 'maps' and '|' not in parts[2]:
                        newmaps = (new['files'].get(f) or {}).get('maps') or {}
                        if any(k.startswith(parts[2] + '|') and not missing(content['maps'][parts[2]], v) for k, v in newmaps.items()):
                            continue          # (a whole map's values: now the race's that was raced there)
                    problems.append('file ' + f + m)
            # and the files must be in today's shape
            st = new['files'].get('swgr_vr_settings.json') or {}
            if st.get('format') != 2 or any(k in st for k in OBSOLETE):
                problems.append('settings file not in today\'s shape: format %s, older keys %s' % (st.get('format'), [k for k in OBSOLETE if k in st]))
            for i, (a, b) in enumerate(zip(old['snaps'], new['snaps'])):
                for k, v in a.items():
                    if k != 'name' and b.get(k) != v:
                        problems.append('%s (%s -> %s): %s %s -> %s' % (i + 1, a['name'], b['name'], k, v, b.get(k)))
            problems += ['CALLBACK ERROR ' + e for e in new.get('errors') or []]
            # picture values for whole maps (2.1.0): the race there has them, the paddock keeps its own
            oldmaps = (files.get('swgr_vr_vehicles.json') or {}).get('maps') or {}
            pic = new.get('pic') or {}
            if 'L_Mastiff_LOOP_B' in oldmaps:
                r = pic.get('race') or {}
                if r.get('place') != 'L_Mastiff_LOOP_B|Debris Dunes|forward|Sunset' or r.get('picCon') != 112 or abs((r.get('picExp') or 0) + 0.3) > 1e-6:
                    problems.append('whole map values not on the race raced there: %s' % r)
                p = pic.get('paddock') or {}
                if p.get('place') != 'L_Mastiff_Paddock' or abs((p.get('picExp') or 0) + 0.5) > 1e-6:
                    problems.append('paddock values: %s' % p)
            # (a file from an older format is kept once as it was, before it is converted)
            sfmt = (files.get('swgr_vr_settings.json') or {}).get('format', 1)
            if sfmt < 2:
                for f, n in (('swgr_vr_settings', sfmt),):
                    bk = '%s_backup_format%d.json' % (f, n)
                    if bk not in new['files']:
                        problems.append('no backup ' + bk)
                    elif missing(files.get(f + '.json', {}), new['files'][bk]):
                        problems.append('backup ' + bk + ' differs from the old file')
            print('%s -> new: %s' % (tag, 'every saved value kept' if not problems else '%d PROBLEMS' % len(problems)))
            for i, (a, b) in enumerate(zip(old['snaps'], new['snaps'])):
                print('   vehicle %d: %s -> %s' % (i + 1, a['name'], b['name']))
            for p in problems[:30]:
                print('   ' + p)
            bad += len(problems)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print('RESULT:', 'FAIL' if bad else 'OK')
    sys.exit(1 if bad else 0)


main()
