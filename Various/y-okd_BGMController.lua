-- @description BGM Controller
-- @version 1.0
-- @author yukinori-okd
-- @about
--   "BGM"トラックの子トラックとして設定したトラックを、ループ楽曲として順々にフェードしながら鳴らしていくためのスクリプト（LOOPSTART,LOOPLENGTH,LOOPENDに対応）

-- ==================================================
-- 設定 (秒数指定)
-- ==================================================
local FADE_SEC     = 5.0
local GAP_SEC      = 1.2  -- 次のアイテムを配置するまでの間隔
local REMAIN_SEC   = FADE_SEC + GAP_SEC  -- 再生時に残す現在のアイテムの長さ (再生位置から)
local PARENT_TRACK = "BGM" -- 親トラック名 (必要に応じて変更)
-- ==================================================
local APP_NAME = "BGM Controller"

local function ReCalcSec()
  REMAIN_SEC = FADE_SEC + GAP_SEC
end

-- 指定した名前のトラックを取得する関数
local function GetTrackByName(name)
  local count = reaper.CountTracks(0)
  for i = 0, count - 1 do
    local track = reaper.GetTrack(0, i)
    local retval, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if retval and track_name == name then
      return track
    end
  end
  return nil
end

-- 親トラックを指定し、その直下の子トラックリストを取得する関数
local function GetChildTracks(parent_track)
  local children = {}
  local count = reaper.CountTracks(0)
  for i = 0, count - 1 do
    local track = reaper.GetTrack(0, i)
    local track_parent = reaper.GetParentTrack(track)
    if track_parent == parent_track then
      table.insert(children, track)
    end
  end
  return children
end

-- アイテムを複製する関数 (Chunkを使用し、完全なコピーを作成)
local function CloneItem(source_item, track, position)
  local new_item = reaper.AddMediaItemToTrack(track)
  local retval, chunk = reaper.GetItemStateChunk(source_item, "", false)
  reaper.SetItemStateChunk(new_item, chunk, false)
  reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", position)
  reaper.SetMediaItemInfo_Value(new_item, "B_UISEL", 1) -- 選択状態にする
  reaper.UpdateItemInProject(new_item)
  return new_item
end

-- アイテムのループ範囲を取得する関数
local function GetItemLoopRange(item)
  -- シークとループ範囲設定
  local loop_end = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local loop_start = 0

  local take = reaper.GetActiveTake(item)
  if take then
    local marker_count = reaper.GetNumTakeMarkers(take)
    local src = reaper.GetMediaItemTake_Source(take)
    for i = 0, marker_count - 1 do
      local retval, name, color = reaper.GetTakeMarker(take, i)
      if string.lower(name) == "loop" then
        loop_start = retval
      end
    end

    -- Ogg Vorbis Loop Metadata (RPG Maker)
    local source = reaper.GetMediaItemTake_Source(take)
    local sr = reaper.GetMediaSourceSampleRate(source)
    local start_retval, source_loop_start = reaper.GetMediaFileMetadata(source, "VORBIS:LOOPSTART")
    local end_retval, source_loop_end = reaper.GetMediaFileMetadata(source, "VORBIS:LOOPEND")
    local len_retval, source_loop_len = reaper.GetMediaFileMetadata(source, "VORBIS:LOOPLENGTH")
    -- to boolean
    start_retval = (start_retval ~= 0)
    end_retval = (end_retval ~= 0)
    len_retval = (len_retval ~= 0)
    -- to number
    if start_retval then source_loop_start = tonumber(source_loop_start) end
    if end_retval then source_loop_end = tonumber(source_loop_end) end
    if len_retval then source_loop_len = tonumber(source_loop_len) end

    if start_retval then
      if not end_retval and len_retval then
        source_loop_end = source_loop_start + source_loop_len
        end_retval = true
      end
      if end_retval then
        loop_start = source_loop_start / sr
        loop_end = source_loop_end / sr
      end
    end
  end

  return loop_start, loop_end
end


-- ==================================================
-- モード1: 停止時の処理 (リセット & 初期化)
-- ==================================================
local function OnStop()
  reaper.Main_OnCommand(43154, 0)

  reaper.Undo_BeginBlock()

  local track_count = reaper.CountTracks(0)
  if track_count == 0 then return end

  local parent_track = GetTrackByName(PARENT_TRACK)
  if not parent_track then return end

  local child_tracks = GetChildTracks(parent_track)
  if #child_tracks == 0 then return end

  -- 1. すべてのトラックの先頭アイテム(インデックス0)以外を削除
  for _, track in ipairs(child_tracks) do
    local item_count = reaper.CountTrackMediaItems(track)
    -- 後ろから削除していく（インデックスずれ防止）
    for j = item_count - 1, 1, -1 do
      local item = reaper.GetTrackMediaItem(track, j)
      reaper.DeleteTrackMediaItem(track, item)
    end
  end

  -- 2. 一番初めの子トラックの一番初めのアイテムをコピーして、プロジェクト末尾に配置
  local track1 = child_tracks[1] -- Track 1 (Index 0)
  local source_item = reaper.GetTrackMediaItem(track1, 0)

  if source_item then
    -- プロジェクトの末尾（何も置いていない時間）を取得
    local project_end = reaper.GetProjectLength(0)
    -- 安全マージンとして少し離す（例: +2秒）
    local insert_pos = project_end + 2.0

    -- アイテムをコピー
    local new_item = CloneItem(source_item, track1, insert_pos)

    -- 仕様の適用: ミュート解除、フェード無し
    reaper.SetMediaItemInfo_Value(new_item, "B_MUTE", 0)
    reaper.SetMediaItemInfo_Value(new_item, "D_FADEINLEN", 0)
    reaper.SetMediaItemInfo_Value(new_item, "D_FADEOUTLEN", 0)

    -- シークとループ範囲設定
    local loop_start, loop_end = GetItemLoopRange(new_item)
    loop_start = insert_pos + loop_start
    loop_end = insert_pos + loop_end

    reaper.SetEditCurPos(insert_pos, true, true)
    reaper.GetSet_LoopTimeRange(true, true, loop_start, loop_end, false)
  end

  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Reset Sequence and Initialize", -1)
end

-- ==================================================
-- モード2: 再生時の処理 (シーケンス進行)
-- ==================================================
local function OnPlay()
  reaper.Undo_BeginBlock()

  local parent_track = GetTrackByName(PARENT_TRACK)
  if not parent_track then return end

  local child_tracks = GetChildTracks(parent_track)
  if #child_tracks == 0 then return end

  local play_pos = reaper.GetPlayPosition()
  local current_item = nil
  local current_track = nil
  local current_track_idx = -1

  -- 現在再生中のアイテムを探す
  local track_count = reaper.CountTracks(0)

  for idx, track in ipairs(child_tracks) do
    local item_count = reaper.CountTrackMediaItems(track)
    for j = 0, item_count - 1 do
      local item = reaper.GetTrackMediaItem(track, j)
      local start_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      local end_pos = start_pos + len

      if play_pos >= start_pos and play_pos < end_pos then
        current_item = item
        current_track = track
        current_track_idx = idx
        break
      end
    end
    if current_item then break end
  end

  if not current_item then
    reaper.Undo_EndBlock("Sequence: No item playing", -1)
    return
  end

  -- 次のトラックの取得と条件チェック
  if current_track_idx == -1 then
    reaper.Undo_EndBlock("Sequence: Current track not found", -1)
    return
  end
  if current_track_idx >= track_count then
    reaper.Undo_EndBlock("Sequence: No next track", -1)
    return
  end

  local next_track_idx = current_track_idx + 1
  local next_track = child_tracks[next_track_idx]

  -- A. 現在再生されているアイテムの処理
  local new_end_pos = play_pos + REMAIN_SEC
  local current_end_pos = reaper.GetMediaItemInfo_Value(current_item, "D_LENGTH") + reaper.GetMediaItemInfo_Value(current_item, "D_POSITION")
  if new_end_pos < current_end_pos then
    reaper.SetMediaItemInfo_Value(current_item, "D_LENGTH", new_end_pos - reaper.GetMediaItemInfo_Value(current_item, "D_POSITION"))
    reaper.SetMediaItemInfo_Value(current_item, "D_FADEOUTLEN", FADE_SEC)
  end

  -- 末尾側の別アイテムを削除 (同トラック内で、このアイテムより後ろにあるもの)
  local cur_track_item_count = reaper.CountTrackMediaItems(current_track)
  for j = cur_track_item_count - 1, 0, -1 do
    local item = reaper.GetTrackMediaItem(current_track, j)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    if pos > new_end_pos then
      reaper.DeleteTrackMediaItem(current_track, item)
    end
  end

  if next_track then
    local next_track_items = reaper.CountTrackMediaItems(next_track)

    -- 条件: 次のトラックのアイテム数が1つのみ、または（論理的に）次のトラックがない場合
    -- ※既にループバック処理を入れているため、next_trackのアイテム数チェックを行う
    if next_track_items == 1 or next_track_idx >= track_count then

      -- B. 次トラックの先頭アイテムのコピー処理
      local source_item_next = reaper.GetTrackMediaItem(next_track, 0)
      if source_item_next then
        local loop_start, loop_end = GetItemLoopRange(source_item_next)

        -- コピー1: 現在の再生位置 + 1秒
        local pos1 = play_pos + GAP_SEC
        local copy1 = CloneItem(source_item_next, next_track, pos1)
        reaper.SetMediaItemInfo_Value(copy1, "B_MUTE", 0)
        reaper.SetMediaItemInfo_Value(copy1, "D_FADEINLEN", FADE_SEC) -- 指定通りフェードイン2秒
        reaper.SetMediaItemInfo_Value(copy1, "D_FADEOUTLEN", 0)
        reaper.SetMediaItemInfo_Value(copy1, "D_LENGTH", loop_end)

        -- コピー2: 現在の再生位置 + コピーアイテムの長さ + 1秒
        -- 仕様解釈: 「現在の再生位置 + コピーアイテムの長さ + 1秒」が開始位置
        -- 数式: PlayPos + SourceLen + 1.0
        -- 注意: コピー1の終了位置は (PlayPos + 1.0) + SourceLen なので、コピー2はコピー1の直後に来ることになります。
        local pos2 = play_pos + loop_end + GAP_SEC
        local copy2 = CloneItem(source_item_next, next_track, pos2)
        reaper.SetMediaItemInfo_Value(copy2, "B_MUTE", 0)
        reaper.SetMediaItemInfo_Value(copy2, "D_FADEINLEN", 0)
        reaper.SetMediaItemInfo_Value(copy2, "D_FADEOUTLEN", 0)

        -- C. ループ設定 (2つ目のアイテムの範囲)
        local take = reaper.GetActiveTake(copy2)
        reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", loop_start) -- スナップオフセットをリセット
        reaper.SetMediaItemInfo_Value(copy2, "D_LENGTH", loop_end - loop_start) -- ループ範囲に合わせて長さを調整
        loop_end = pos2 + (loop_end - loop_start)

        reaper.GetSet_LoopTimeRange(true, true, pos2, loop_end, false)

        -- ビューをスクロール（オプション：作業しやすいように）
        reaper.UpdateArrange()
      end
    end
  end

  reaper.Undo_EndBlock("Sequence: Next Step", -1)
end


package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'
local ctx = ImGui.CreateContext(APP_NAME)

local function loop()
  local bg_col = reaper.GetThemeColor("col_mixerbg", 0)
  bg_col = (bg_col << 8) | 0xff
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, bg_col)

  local visible, open = ImGui.Begin(ctx, APP_NAME, true)

  if visible then
    local rv, new_val = ImGui.DragDouble(ctx, "Cross Fade Time", FADE_SEC, 0.1, 0.001, 1000)
    if rv then
      FADE_SEC = new_val
      ReCalcSec()
    end
    local rv, new_val = ImGui.DragDouble(ctx, "Item Gap Time", GAP_SEC, 0.1, 0.001, 1000)
    if rv then
      GAP_SEC = new_val
      ReCalcSec()
    end


    if ImGui.Button(ctx, "Play", -1, 30) then
      reaper.OnPlayButton()
      reaper.GetSetRepeat(1)
    end
    if ImGui.Button(ctx, "Stop", -1, 30) then
      reaper.OnStopButton()
    end
    if ImGui.Button(ctx, "Next", -1, 30) then
      local play_state = reaper.GetPlayState()

      if play_state == 0 then
        -- 停止中
        OnStop()
      else
        -- 再生中 (または録音中など)
        OnPlay()
      end
    end
    if ImGui.Button(ctx, "Init", -1, 30) then
      OnStop()
    end
    ImGui.End(ctx)
  end
  if open then
    reaper.defer(loop)
  end

  ImGui.PopStyleColor(ctx, 1)
end

reaper.defer(loop)
