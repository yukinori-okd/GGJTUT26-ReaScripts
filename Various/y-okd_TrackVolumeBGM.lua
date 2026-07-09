-- @description MIDI CC to BGM Track Volume
-- @version 1.0
-- @author yukinori-okd
-- @about
--   MIDI CCメッセージを用い"BGM"トラックのボリュームを変更するためのスクリプト

local TARGET_NAME = "BGM"


-- 1. アクションの発動コンテキストを取得 (MIDI CCの値を取得)
local is_new, filename, sectionID, cmdID, mode, resolution, val = reaper.get_action_context()

-- MIDI入力以外、または値が無効な場合は終了
if not is_new or val == -1 then return end

-- 2. "SE" という名前のトラックを探す
local target_track = nil
local track_count = reaper.CountTracks(0) -- 全トラック数

for i = 0, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    -- トラック名を取得 ("P_NAME")
    local retval, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

    if track_name == TARGET_NAME then
        target_track = track
        break -- 見つかったらループを抜ける
    end
end

-- 3. トラックが見つかった場合のみボリュームを変更
if target_track then
    -- MIDI値 (0-127) を正規化 (0.0 - 1.0)
    local max_midi = 127
    if resolution > 0 then max_midi = resolution end

    local normalized = val / max_midi

    -- カーブ処理 (聴感を自然にするための二乗カーブ)
    -- 0.0(無音) 〜 1.0(0dB) になります
    local vol = normalized * normalized

    -- ボリュームを適用
    reaper.SetMediaTrackInfo_Value(target_track, "D_VOL", vol)
end
