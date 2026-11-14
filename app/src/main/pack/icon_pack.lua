-- SPDX-License-Identifier: AGPL-3.0-only
-- p67 .043 CIPK delivery: bounded copies, bounded read-back, atomic 128-byte index.
-- The visual shell is shared with Chaos-Module's original icon delivery watchface.
local lvgl = require("lvgl")
local V_DEEP, V_MID, V_LINE2 = 0x1C1C1E, 0x2C2C2E, 0x2A2A2C
local V_TXT, V_TXT2, V_OK, V_ERR = 0xF2F2F2, 0xB3B3B3, 0x30D158, 0xFF453A
local V_ACC_BG, V_R, F_BODY = 0x2563EB, 24, "MiSans-Regular"
local DATA_DIR = "/data/chaos"
local ICON_DIR = DATA_DIR .. "/icons"
local INDEX_PATH = ICON_DIR .. "/index.txt"
local INDEX_TMP = ICON_DIR .. "/index.tmp"
local PACK_NAME = "__PACK_NAME__"
local PACK_TITLE = "__PACK_TITLE__"
local PACK_RESOURCE = (SCRIPT_PATH or "") .. "pack.bin"
local CHUNK, TOTAL_MAX = 65536, 16777215
local ALLOWED = { -- generated from the p67 static stem mapping
  ["activities"] = true,
  ["aivs"] = true,
  ["alarm"] = true,
  ["alipay"] = true,
  ["breath"] = true,
  ["cal_background"] = true,
  ["calendar"] = true,
  ["camera"] = true,
  ["card"] = true,
  ["card_access_card_01"] = true,
  ["card_access_card_02"] = true,
  ["card_access_card_03"] = true,
  ["card_access_card_04"] = true,
  ["card_access_card_sdoor"] = true,
  ["card_access_card_work"] = true,
  ["card_bank_card_mastercard"] = true,
  ["card_bank_card_visa"] = true,
  ["card_car_card_biyadi"] = true,
  ["card_car_card_brnd"] = true,
  ["card_car_card_fangchengbao"] = true,
  ["card_car_card_lot1"] = true,
  ["card_car_card_tengshi"] = true,
  ["card_car_card_xia1"] = true,
  ["card_car_card_yangwang"] = true,
  ["card_car_card_yu7"] = true,
  ["card_ecc"] = true,
  ["card_ecc_student"] = true,
  ["card_jiangsu_transit_card_jiangsuchangzhou"] = true,
  ["card_jiangsu_transit_card_jiangsuhuaian"] = true,
  ["card_jiangsu_transit_card_jiangsuhuaihai"] = true,
  ["card_jiangsu_transit_card_jiangsujinling"] = true,
  ["card_jiangsu_transit_card_jiangsukunshan"] = true,
  ["card_jiangsu_transit_card_jiangsulianyungang"] = true,
  ["card_jiangsu_transit_card_jiangsunantong"] = true,
  ["card_jiangsu_transit_card_jiangsusuqian"] = true,
  ["card_jiangsu_transit_card_jiangsusuzhou"] = true,
  ["card_jiangsu_transit_card_jiangsutaizhou"] = true,
  ["card_jiangsu_transit_card_jiangsuwuxi"] = true,
  ["card_jiangsu_transit_card_jiangsuyancheng"] = true,
  ["card_jiangsu_transit_card_jiangsuyangzhou"] = true,
  ["card_jiangsu_transit_card_jiangsuzhenjiang"] = true,
  ["card_lingnan_transit_card_lingnanchaozhou"] = true,
  ["card_lingnan_transit_card_lingnanguangfo"] = true,
  ["card_lingnan_transit_card_lingnanheyuanyu"] = true,
  ["card_lingnan_transit_card_lingnanhonghai"] = true,
  ["card_lingnan_transit_card_lingnanlingyun"] = true,
  ["card_lingnan_transit_card_lingnanmaocheng"] = true,
  ["card_lingnan_transit_card_lingnanmojiang"] = true,
  ["card_lingnan_transit_card_lingnanrongjiang"] = true,
  ["card_lingnan_transit_card_lingnanshaozhou"] = true,
  ["card_lingnan_transit_card_lingnanwuyi"] = true,
  ["card_lingnan_transit_card_lingnanyangcheng"] = true,
  ["card_lingnan_transit_card_lingnanzhaoqing"] = true,
  ["card_transit_card_beijing"] = true,
  ["card_transit_card_chongqing"] = true,
  ["card_transit_card_dalian"] = true,
  ["card_transit_card_ganzhou"] = true,
  ["card_transit_card_guangxi"] = true,
  ["card_transit_card_haerbin"] = true,
  ["card_transit_card_hainan"] = true,
  ["card_transit_card_hangzhou"] = true,
  ["card_transit_card_hefei"] = true,
  ["card_transit_card_hongcheng"] = true,
  ["card_transit_card_hongshan"] = true,
  ["card_transit_card_jilin"] = true,
  ["card_transit_card_jinhua"] = true,
  ["card_transit_card_kunming"] = true,
  ["card_transit_card_lanzhou"] = true,
  ["card_transit_card_ningbo"] = true,
  ["card_transit_card_qingdao"] = true,
  ["card_transit_card_quancheng"] = true,
  ["card_transit_card_rongcheng"] = true,
  ["card_transit_card_shanghai"] = true,
  ["card_transit_card_shaoxing"] = true,
  ["card_transit_card_shengjing"] = true,
  ["card_transit_card_shenzhen"] = true,
  ["card_transit_card_taizhou"] = true,
  ["card_transit_card_tianfu"] = true,
  ["card_transit_card_tianjin"] = true,
  ["card_transit_card_tuocheng"] = true,
  ["card_transit_card_wuhan"] = true,
  ["card_transit_card_xiamen"] = true,
  ["card_transit_card_xian"] = true,
  ["card_transit_card_xiaoxiang"] = true,
  ["card_transit_card_xizang"] = true,
  ["card_transit_card_yanzhao"] = true,
  ["card_transit_card_yinchuan"] = true,
  ["card_transit_card_zhengzhou"] = true,
  ["card_transit_card_zhuhai"] = true,
  ["card_widget22"] = true,
  ["card_widget_card_bg"] = true,
  ["chronograph"] = true,
  ["compass"] = true,
  ["ctrl_alarm"] = true,
  ["ctrl_battery"] = true,
  ["ctrl_bright"] = true,
  ["ctrl_disturb"] = true,
  ["ctrl_dnd"] = true,
  ["ctrl_findphone"] = true,
  ["ctrl_flashlight"] = true,
  ["ctrl_game"] = true,
  ["ctrl_phone_conn"] = true,
  ["ctrl_phone_disconn"] = true,
  ["ctrl_raise"] = true,
  ["ctrl_setting"] = true,
  ["dealt"] = true,
  ["findphone"] = true,
  ["flashlight"] = true,
  ["heartrate"] = true,
  ["innovation_research"] = true,
  ["interconnect"] = true,
  ["mijia"] = true,
  ["music"] = true,
  ["mute"] = true,
  ["oxygen"] = true,
  ["perpetual_calendar"] = true,
  ["pressure"] = true,
  ["recorder"] = true,
  ["set_battery"] = true,
  ["set_desktop"] = true,
  ["set_display"] = true,
  ["set_disturb"] = true,
  ["set_hr"] = true,
  ["set_motion"] = true,
  ["set_mydevice"] = true,
  ["set_notify"] = true,
  ["set_preference"] = true,
  ["set_safe"] = true,
  ["set_wrist"] = true,
  ["settings"] = true,
  ["share"] = true,
  ["sleep"] = true,
  ["sports"] = true,
  ["sports_course"] = true,
  ["sports_record"] = true,
  ["sports_status"] = true,
  ["timer"] = true,
  ["todo"] = true,
  ["tomato_clock"] = true,
  ["vitality"] = true,
  ["weather"] = true,
  ["womenhealth"] = true,
  ["worldclock"] = true,
  ["wxpay"] = true,
}
local ANIMATED = {
  ["activities"] = true,
  ["aivs"] = true,
  ["alarm"] = true,
  ["alipay"] = true,
  ["breath"] = true,
  ["calendar"] = true,
  ["camera"] = true,
  ["card"] = true,
  ["chronograph"] = true,
  ["compass"] = true,
  ["dealt"] = true,
  ["findphone"] = true,
  ["flashlight"] = true,
  ["heartrate"] = true,
  ["innovation_research"] = true,
  ["interconnect"] = true,
  ["mijia"] = true,
  ["music"] = true,
  ["mute"] = true,
  ["oxygen"] = true,
  ["perpetual_calendar"] = true,
  ["pressure"] = true,
  ["recorder"] = true,
  ["settings"] = true,
  ["share"] = true,
  ["sleep"] = true,
  ["sports"] = true,
  ["sports_course"] = true,
  ["sports_record"] = true,
  ["sports_status"] = true,
  ["timer"] = true,
  ["todo"] = true,
  ["tomato_clock"] = true,
  ["vitality"] = true,
  ["weather"] = true,
  ["womenhealth"] = true,
  ["worldclock"] = true,
  ["wxpay"] = true,
}
local job = { stage = 0, src = nil, dst = nil, verify = nil }
local status_label, timer

local function set_status(text, color)
  if status_label then pcall(function() status_label:set { text = tostring(text), text_color = color or V_TXT2 } end) end
end
local function u16(s, p)
  local a, b = s:byte(p, p + 1)
  return b and (a + b * 256) or nil
end
local function u32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  return d and (a + b * 256 + c * 65536 + d * 16777216) or nil
end
local function exact(file, n)
  local parts, remaining = {}, n
  while remaining > 0 do
    local block = file:read(math.min(remaining, CHUNK))
    if type(block) ~= "string" or #block == 0 or #block > remaining then return nil end
    parts[#parts + 1], remaining = block, remaining - #block
  end
  return table.concat(parts)
end
local function close(file)
  local ok, result = pcall(file.close, file)
  return ok and result ~= nil and result ~= false
end
local function close_files()
  for _, key in ipairs { "src", "dst", "verify" } do
    if job[key] then pcall(function() job[key]:close() end); job[key] = nil end
  end
end
local function finish(ok, text)
  job.stage = 0
  close_files()
  if not ok and job.current_path then pcall(os.remove, job.current_path) end
  if not ok then pcall(os.remove, INDEX_TMP) end
  if timer then pcall(function() timer:pause() end) end
  set_status(text, ok and V_OK or V_ERR)
end
local function checksum(block, offset, sum)
  for i = 1, #block do sum = sum + block:byte(i) * (offset + i) end
  return sum % 4294967296
end
local function read_index()
  local file = io.open(INDEX_PATH, "rb")
  if not file then return {} end
  local raw = exact(file, 128) or ""
  close(file)
  local rows, used = {}, {}
  for i = 0, 7 do
    local row = raw:sub(i * 16 + 1, i * 16 + 16)
    local id = tonumber(row:sub(1, 2))
    local name = row:sub(4, 15):gsub("%s+$", "")
    if #row == 16 and row:sub(3, 3) == " " and row:sub(16) == "\n" and id and id >= 1 and id <= 8 and #name > 0 and not used[id] then
      rows[#rows + 1], used[id] = { id = id, name = name }, true
    end
  end
  return rows
end
local function pick_pack(rows)
  local used = {}
  for _, row in ipairs(rows) do
    used[row.id] = true
    if row.name == PACK_NAME then return row.id end
  end
  for id = 1, 8 do
    if not used[id] then rows[#rows + 1] = { id = id, name = PACK_NAME }; return id end
  end
end
local function render_index(rows)
  local result = {}
  for i = 1, 8 do
    local row = rows[i]
    result[i] = row and string.format("%02d %s%s\n", row.id, row.name, string.rep(" ", 12 - #row.name)) or string.rep(" ", 16)
  end
  return table.concat(result)
end
local function write_index(rows)
  local expected = render_index(rows)
  local file = io.open(INDEX_TMP, "wb")
  if not file then return false end
  local ok, result = pcall(file.write, file, expected)
  local closed = close(file)
  if not ok or not result or not closed then pcall(os.remove, INDEX_TMP); return false end
  file = io.open(INDEX_TMP, "rb")
  if not file then pcall(os.remove, INDEX_TMP); return false end
  local actual = exact(file, 128)
  local tail, read_error = file:read(1)
  closed = close(file)
  if not closed or read_error or actual ~= expected or (tail and #tail > 0) then pcall(os.remove, INDEX_TMP); return false end
  ok, result = pcall(os.rename, INDEX_TMP, INDEX_PATH)
  if not ok or not result then pcall(os.remove, INDEX_TMP); return false end
  return true
end
local function role(name)
  if #name < 5 or #name > 64 or not name:match("^[A-Za-z0-9_]+%.bin$") then return nil end
  if name == "animations.bin" then return "index" end
  local stem = name:sub(1, -5)
  if stem:sub(-5) == "_anim" then return ANIMATED[stem:sub(1, -6)] and "animation" or nil end
  return ALLOWED[stem] and "static" or nil
end
local function check_head()
  if job.kind == "animation" then
    local h = job.head
    local count = u16(h, 9)
    return #h == 60 and h:sub(1, 4) == "DGF1" and u16(h, 5) == 96 and u16(h, 7) == 96 and
      count and count >= 1 and count <= 256 and u16(h, 11) == 0 and u32(h, 21) == 1084 and
      u32(h, 25) == 1084 + count * 12 and job.length > 1084 + count * 12
  elseif job.kind == "index" then
    local h = job.head
    return job.length == 20 and #h == 20 and h:sub(1, 4) == "CIA1" and u16(h, 5) == 96 and
      u16(h, 7) == 96 and u16(h, 9) == 38 and u16(h, 11) == 0 and u32(h, 17) < 64
  end
  return true
end
local function step()
  if job.stage == 1 then
    if #PACK_NAME < 1 or #PACK_NAME > 12 or not PACK_NAME:match("^[A-Za-z0-9_-]+$") then finish(false, "包短名不合法"); return end
    local rows = read_index()
    local id = pick_pack(rows)
    if not id then finish(false, "图标包已满(8)，请先删一个"); return end
    local src = io.open(PACK_RESOURCE, "rb")
    if not src then finish(false, "容器里没有 pack.bin"); return end
    job.src = src
    local header = exact(src, 8)
    local count = header and u32(header, 5)
    if not header or header:sub(1, 4) ~= "CIPK" or count < 1 or count > 256 then finish(false, "CIPK 头或文件数不合法"); return end
    job.pack, job.rows, job.count, job.index = id, rows, count, 0
    job.total, job.seen, job.files = 8, {}, {}
    job.dir = ICON_DIR .. "/" .. string.format("%02d", id)
    -- A same-name replacement must first be deselected in Chaos, as documented.
    os.execute("rm -rf " .. job.dir)
    os.execute("mkdir -p " .. job.dir)
    job.stage = 2
    set_status(PACK_NAME .. " 解包 0/" .. count)
    return
  end
  if job.stage == 2 then
    if not job.dst then
      if job.index == job.count then
        local tail, read_error = job.src:read(1)
        if read_error or (tail and #tail > 0) then finish(false, "CIPK 尾部有多余数据或读取失败"); return end
        close(job.src); job.src = nil
        job.verify_index, job.stage = 1, 3
        return
      end
      local header = exact(job.src, 5)
      local length, name_len = header and u32(header, 1), header and header:byte(5)
      if not name_len or name_len < 1 or name_len > 64 then finish(false, "资源头被截断或名字过长"); return end
      local name = exact(job.src, name_len)
      local kind = name and role(name)
      local limit = kind == "animation" and 1048576 or 524288
      if not kind or job.seen[name] or not length or length < 1 or length > limit then finish(false, "资源名重复、未知或长度不合法"); return end
      job.total = job.total + 5 + name_len + length
      if job.total > TOTAL_MAX then finish(false, "CIPK 超过 24 位容量上限"); return end
      local path = job.dir .. "/" .. name
      local dst = io.open(path, "wb")
      if not dst then finish(false, "无法创建资源文件"); return end
      job.current_path, job.dst, job.name, job.kind = path, dst, name, kind
      job.seen[name], job.length, job.moved, job.sum, job.head = true, length, 0, 0, ""
      return
    end
    local want = math.min(CHUNK, job.length - job.moved)
    local block = job.src:read(want)
    if type(block) ~= "string" or #block == 0 or #block > want then finish(false, "资源数据被截断"); return end
    if #job.head < 60 then job.head = job.head .. block:sub(1, 60 - #job.head) end
    local ok, result = pcall(job.dst.write, job.dst, block)
    if not ok or not result then finish(false, "资源写入失败，请检查空间"); return end
    job.sum = checksum(block, job.moved, job.sum)
    job.moved = job.moved + #block
    if job.moved == job.length then
      if not close(job.dst) then job.dst = nil; finish(false, "资源关闭失败"); return end
      job.dst = nil
      if not check_head() then finish(false, "动画或索引头不合法"); return end
      job.files[#job.files + 1] = { path = job.current_path, length = job.length, sum = job.sum }
      job.current_path = nil
      job.index = job.index + 1
      set_status(PACK_NAME .. " 解包 " .. job.index .. "/" .. job.count)
    end
    return
  end
  if job.stage == 3 then
    local entry = job.files[job.verify_index]
    if not entry then job.stage = 4; return end
    if not job.verify then
      job.verify = io.open(entry.path, "rb")
      if not job.verify then finish(false, "资源回读失败，清单未提交"); return end
      job.checked, job.checksum = 0, 0
    end
    if job.checked < entry.length then
      local want = math.min(CHUNK, entry.length - job.checked)
      local block = job.verify:read(want)
      if type(block) ~= "string" or #block == 0 or #block > want then finish(false, "资源回读不完整，清单未提交"); return end
      job.checksum = checksum(block, job.checked, job.checksum)
      job.checked = job.checked + #block
    else
      local tail, read_error = job.verify:read(1)
      local ok = close(job.verify); job.verify = nil
      if not ok or read_error or (tail and #tail > 0) or job.checksum ~= entry.sum then finish(false, "资源回读校验失败，清单未提交"); return end
      job.verify_index = job.verify_index + 1
    end
    return
  end
  if job.stage == 4 then
    if not write_index(job.rows) then finish(false, "清单写入失败，旧清单未替换"); return end
    finish(true, "已投递 " .. job.count .. " 个文件，包号 " .. string.format("%02d", job.pack))
  end
end
local function start()
  if job.stage ~= 0 then return end
  if not timer then
    timer = lvgl.Timer {
      period = 200, repeat_count = -1, paused = true,
      cb = function(ti)
        local ok, err = pcall(step)
        if not ok then finish(false, "投递失败: " .. tostring(err)); return end
        if job.stage ~= 0 then ti:ready() end
      end,
    }
    if not timer then set_status("定时器创建失败", V_ERR); return end
  end
  job.stage, job.current_path = 1, nil
  pcall(function() timer:resume() end)
  set_status("开始...")
end

-- ===== 界面(与主包安装器/字体包同一套设计语言) =====

local W = lvgl.HOR_RES()
local H = lvgl.VER_RES()

local root = lvgl.Object(nil, {
  w = W, h = H,
  outline_width = 0, border_width = 0, pad_all = 0,
  bg_opa = lvgl.OPA(100), bg_color = V_DEEP,
})
-- 容器必须凑齐三件事, 少一件长按表盘就进不了表盘选择页:
-- clear_flag(SCROLLABLE) + add_flag(EVENT_BUBBLE) + 根对象 add_flag(CLICKABLE)
root:clear_flag(lvgl.FLAG.SCROLLABLE)
root:add_flag(lvgl.FLAG.CLICKABLE)
root:add_flag(lvgl.FLAG.EVENT_BUBBLE)

lvgl.Label(root, {
  text = PACK_TITLE,
  text_color = V_TXT,
  text_font = lvgl.Font(F_BODY, 40),
  align = { type = lvgl.ALIGN.CENTER, x_ofs = 0, y_ofs = -170 },
})

local card = lvgl.Object(root, {
  w = W - 32, h = 150,
  bg_opa = lvgl.OPA(100), bg_color = V_MID,
  border_width = 1, border_color = V_LINE2,
  radius = V_R, pad_all = 0,
  align = { type = lvgl.ALIGN.CENTER, x_ofs = 0, y_ofs = -20 },
})
card:clear_flag(lvgl.FLAG.SCROLLABLE)
card:add_flag(lvgl.FLAG.EVENT_BUBBLE)
status_label = lvgl.Label(card, {
  text = PACK_NAME .. " 已加载",
  text_color = V_TXT2,
  text_font = lvgl.Font(F_BODY, 22),
  align = { type = lvgl.ALIGN.CENTER, x_ofs = 0, y_ofs = 0 },
})

local btn = lvgl.Object(root, {
  w = W - 32, h = 64,
  bg_color = V_ACC_BG, bg_opa = lvgl.OPA(100),
  border_width = 1, border_color = V_ACC_BG,
  radius = V_R, pad_all = 0,
  align = { type = lvgl.ALIGN.CENTER, x_ofs = 0, y_ofs = 110 },
})
btn:clear_flag(lvgl.FLAG.SCROLLABLE)
btn:add_flag(lvgl.FLAG.CLICKABLE)
btn:add_flag(lvgl.FLAG.EVENT_BUBBLE)
lvgl.Label(btn, {
  text = "投递图标",
  text_color = V_TXT,
  text_font = lvgl.Font(F_BODY, 24),
  align = { type = lvgl.ALIGN.CENTER, x_ofs = 0, y_ofs = 0 },
})
btn:onClicked(function()
  local ok, err = pcall(start)
  if not ok then set_status("启动失败: " .. tostring(err), V_ERR) end
end)
