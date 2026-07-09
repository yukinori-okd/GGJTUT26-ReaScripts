package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'
local app_name = "Pon SE Manager"
local ctx = ImGui.CreateContext(app_name)

local status = {}
local PARENT_TRACK = "SE" -- 親トラック名
local gap_sec = 0.1 -- SEを鳴らすまでの間隔（秒）

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

-- アイテムを複製する関数
local function CloneItem(source_item, track, position)
  local new_item = reaper.AddMediaItemToTrack(track)
  local retval, chunk = reaper.GetItemStateChunk(source_item, "", false)
  reaper.SetItemStateChunk(new_item, chunk, false)
  reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", position)
  reaper.SetMediaItemInfo_Value(new_item, "B_UISEL", 1) -- 選択状態にする
  reaper.UpdateItemInProject(new_item)
  return new_item
end

-- 【追加機能】同一トラックにある「ソース以外の」古いアイテムを削除する
local function ClearOtherInstances(track, source_item)
  local count = reaper.CountTrackMediaItems(track)
  -- 削除操作を行うため、インデックスがズレないよう後ろからループする
  for i = count - 1, 0, -1 do
    local item = reaper.GetTrackMediaItem(track, i)
    -- ソースアイテム（テンプレート）は消さない
    if item ~= source_item then
      reaper.DeleteTrackMediaItem(track, item)
    end
  end
end

-- 【追加機能】再生位置を監視し、アイテムが終わったら削除する関数
local function AutoDeleteWatcher(track_id, target_item)
  -- アイテムが（手動削除などで）既に存在しない場合は監視終了
  if not reaper.ValidatePtr(target_item, "MediaItem*") then return end

  local play_state = reaper.GetPlayState() -- 0=停止, 1=再生中

  -- 再生中の場合のみチェック
  if play_state == 1 then
    local cur_pos = reaper.GetPlayPosition()
    local item_pos = reaper.GetMediaItemInfo_Value(target_item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(target_item, "D_LENGTH")
    local item_end = item_pos + item_len

    -- 再生位置がアイテムの終了位置を超えたら削除
    if cur_pos <= item_pos - 0.5  or cur_pos >= item_end then
      local track = reaper.GetMediaItem_Track(target_item)
      reaper.DeleteTrackMediaItem(track, target_item)
      reaper.UpdateArrange()
      status[track_id] = nil
      return -- 削除したので監視終了
    end
  end

  -- まだ終わっていない、または停止中の場合は監視を継続
  reaper.defer(function() AutoDeleteWatcher(track_id, target_item) end)
end

-- === メイン処理 ===
local function loop()
  local EXT_SECTION = "SE_RUNNER_SCRIPT_SYSTEM"
  local EXT_KEY = "SE_MESSAGE_QUEUE"

  local visible, open = ImGui.Begin(ctx, app_name, true)
  if visible then
    local se_track = GetTrackByName(PARENT_TRACK)
    if se_track then
      local child_tracks = GetChildTracks(se_track)

      -- メイン
      local msg = reaper.GetExtState(EXT_SECTION, EXT_KEY)
      -- 2. メッセージがあれば処理を行う
      if msg ~= "" then
          for command in string.gmatch(msg, "[^;]+") do
            local track_id = tonumber(command)
            -- reaper.ShowConsoleMsg("コマンド受信: " .. command .. " " .. track_id .. "/" .. #child_tracks .. "\n")

            if track_id > 0 and track_id <= #child_tracks then
              local track = child_tracks[track_id]
              local source_item = reaper.GetTrackMediaItem(track, 0) -- 先頭のアイテムをソースとする

              if source_item then
                reaper.Undo_BeginBlock()

                -- 1. 古いSEアイテムがあれば削除（ソース以外を一掃）
                ClearOtherInstances(track, source_item)

                -- プロジェクトの末尾（何も置いていない時間）を取得 or 再生位置を使用
                -- ※元のコードは play_pos 基準でしたのでそれに合わせます
                local play_pos = reaper.GetPlayPosition()
                local insert_pos = play_pos + gap_sec -- 即座に鳴らすなら play_pos そのまま、少し遅らせるなら + 0.1 など

                -- 2. アイテムをコピー配置
                local new_item = CloneItem(source_item, track, insert_pos)
                status[track_id] = "Playing"

                -- 仕様の適用: ミュート解除、フェード無し
                reaper.SetMediaItemInfo_Value(new_item, "B_MUTE", 0)
                reaper.SetMediaItemInfo_Value(new_item, "D_FADEINLEN", 0)
                reaper.SetMediaItemInfo_Value(new_item, "D_FADEOUTLEN", 0)

                reaper.Undo_EndBlock("Trigger SE", -1)
                reaper.UpdateArrange()

                -- 3. 自動削除の監視を開始 (Undoブロックの外で実行)
                AutoDeleteWatcher(track_id, new_item)
              else
                -- ソースアイテムが見つからない場合 (デバッグ用)
                -- reaper.ShowConsoleMsg("Error: Source item not found on track.\n")
              end
            else
              -- 指定インデックスのトラックが無い場合 (デバッグ用)
              -- reaper.ShowConsoleMsg("Error: Child track index out of range.\n")
            end
          end

          -- 3. 処理が終わったらメッセージをクリアする (これにより1回だけ実行される)
          reaper.SetExtState(EXT_SECTION, EXT_KEY, "", false)
      end


      -- GUI
      local table = ImGui.BeginTable(ctx, "SE Table", 4, 0, 0,0, 0)
      if table then
        ImGui.TableSetupColumn(ctx, "Num", ImGui.TableColumnFlags_WidthFixed, 30.0)
        ImGui.TableSetupColumn(ctx, "Name")
        ImGui.TableSetupColumn(ctx, "Status", ImGui.TableColumnFlags_WidthFixed, 40.0)
        ImGui.TableSetupColumn(ctx, "Action", ImGui.TableColumnFlags_WidthFixed, 40.0)
        ImGui.TableHeadersRow(ctx)
        for i, track in ipairs(child_tracks) do
          ImGui.TableNextColumn(ctx)
          ImGui.Text(ctx, tostring(i))

          ImGui.TableNextColumn(ctx)
          local retval, text = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
          ImGui.Text(ctx, text)

          ImGui.TableNextColumn(ctx)
          ImGui.Text(ctx, status[i] or "None")

          ImGui.TableNextColumn(ctx)
          if ImGui.Button(ctx, "Play##"..tostring(i)) then
            local command = reaper.GetExtState(EXT_SECTION, EXT_KEY)
            command = command .. tostring(i) .. ";"
            reaper.SetExtState(EXT_SECTION, EXT_KEY, command, false)
          end
        end
        ImGui.EndTable(ctx)
      end
    end
    ImGui.End(ctx)
  end

  if open then
    reaper.defer(loop)
  end
end

reaper.defer(loop)
