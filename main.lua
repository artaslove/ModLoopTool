--[[============================================================================
main.lua
============================================================================]]--

--[[

This is an experiment to modify sample loop positions by bonafide@martica.org
portions of this code for handling notes and frequencies, although slightly modified are from:
https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/loot/openos/lib/note.lua

V0.22

ToDo:
  - restoring sample properties on close
  - additional modes of operation such as more choices for what to do in loose mode when a loop point hits a boundary
  - glide option for pitch 
    - glide speed
  - finer control over pitch in general
    - octave, cents
  - bitmaps 
    - markers on sliders
    - start stop button 

eventual goals
  - become aware of the highest and lowest current note(s), either in selected track of composition or currently playing, this enables:
    - better representation in the GUI of the actual note being played 
    - not exceeding playback speed
    - fixing the pitch change with high spdocities
    - random mode
    - the option of using zero crossings

]]

require "process_slicer"

-----------------------------------------------------------------------------------------------------------
-- eventually move the note functions to another file or find the coresponding library that renoise uses... 

local notes = {}
--The reversed table "notes"
local reverseNotes = {}

do
  --All the base notes
  local tempNotes = {
    "c",
    "c#",
    "d",
    "d#",
    "e",
    "f",
    "f#",
    "g",
    "g#",
    "a",
    "a#",
    "b"
    }
  --The table containing all the standard notes and # semitones in correct order, temporarily
  local sNotes = {}
  --The table containing all the b semitones
  local bNotes = {}

  --Registers all possible notes in order
  do
    table.insert(sNotes,"a0")
    table.insert(sNotes,"a#0")
    table.insert(bNotes,"bb0")
    table.insert(sNotes,"b0")
    for i = 1,7 do
      for _,v in ipairs(tempNotes) do
        table.insert(sNotes,v..tostring(i))
        if #v == 1 and v ~= "c" and v ~= "f" then
          table.insert(bNotes,v.."b"..tostring(i))
        end
      end
    end
  end
  for i=21,107 do
    notes[sNotes[i-20]]=tostring(i)
  end

  --Reversing the whole table in reverseNotes, used for noteget
  do
    for k,v in pairs(notes) do
      reverseNotes[tonumber(v)]=k
    end
  end

  --This is registered after reverseNotes to avoid conflicts
  for k,v in ipairs(bNotes) do
    notes[v]=tostring(notes[string.gsub(v,"(.)b(.)","%1%2")]-1)
  end
end

--Converts String or MIDI code into frequency
function notefreq(n)
  if type(n) == "string" then
    n = string.lower(n)
    if tonumber(notes[n])~=nil then
      return math.pow(2,(tonumber(notes[n])-69)/12)*440
    else
      error("Wrong input "..tostring(n).." given to notefreq, needs to be <note>[semitone sign]<octave>, e.g. A#0 or Gb4",2)
    end
  elseif type(n) == "number" then
    return math.pow(2,(n-69)/12)*440
  else
    error("Wrong input "..tostring(n).." given to notefreq, needs to be a number or a string",2)
  end
end

--Converts a MIDI value back into a string
function notename(n)
  n = tonumber(n)
  if reverseNotes[n] then
    return string.upper(string.match(reverseNotes[n],"^(.)"))..string.gsub(reverseNotes[n],"^.(.*)","%1")
  else
    error("Attempt to get a note for a non-exsisting MIDI code",2)
  end
end

-- end note functions
-------------------------------------------------------------------------------------------------------------

local options = renoise.Document.create("ScriptingToolPreferences") {
  maxspeed = 512,
  maxmaxspeed = 512,
  maxminframes = 2048,
  startspd = 10,
  startenable = true,
  endspd = 20,
  endenable = true,
  minframes = 1, 
  speed = 128, 
  thenote = 48,
  modetype = 2,
  restoresample = true,
  minframepitch = false,
  collisiontype = 1,
  returntopitch = false
}

originalstartpos = nil
startpos = nil
originalendpos = nil
endpos = nil
originalloopmode = nil
loopmode = nil
originallastframe = nil
targetframes = nil
onecycle = nil
rsong = nil
selected_sample = nil
lastsample = nil
lastframe = nil
sample_rate = nil
pat_track = nil
sel_line = nil
track = nil
sflip = false
eflip = false
vflip = false
gui = nil
direction = nil
nosample = true


function main(update_progress_func)
  local s = nil
  local e = nil

  while true do 
   if (rsong.selected_sample ~= nil) then 
    if (lastsample ~= rsong.selected_sample_index) then
      if restoresample == true then
        rsong.selected_sample[lastsample].loop_start = originalstartpos
        rsong.selected_sample[lastsample].loop_end = originalendpos
        rsong.selected_sample[lastsample].loop_mode = originalstartpos
      end
      selected_sample = rsong.selected_sample
      originalstartpos = selected_sample.loop_start
      originalendpos = selected.sample.loop_end
      originalloopmode = selected_sample.loop_mode
      startpos = selected_sample.loop_start
      endpos = selected_sample.loop_end
      sample_rate = selected_sample.sample_buffer.sample_rate
    end  
    lastframe = selected_sample.sample_buffer.number_of_frames
    if lastframe ~= originallastframe then -- user is adding or deleting sample content
      if endpos > lastframe then
        endpos = lastframe
      end
      if startpos + options.minframes.value > lastframe then
        startpos = lastframe - options.minframes.value
      end
      originallastframe = lastframe
    end
    if options.maxspeed.value > (lastframe / 2) then
      options.maxspeed.value = lastframe / 2
    end
    if options.minframes.value > lastframe then
      options.minframes.value = lastframe    
    end

    onecycle = 1/notefreq(options.thenote.value)
    targetframes = onecycle * sample_rate
    
    -- Here begins the logic for actually moving the loop points around...
    --
    -- 1 - loose   - the start and end points move back and forth with unique spdocities
    -- 2 - pitch   - the start and end points move together in order to create a pitch
    -- 3 - ?????
  
    if (options.modetype.value == 1) then -- loose
      if options.returntopitch.value == true then
        options.minframes.value = targetframes
      end
      if options.startenable.value == true and startpos > 1 and startpos < endpos and startpos < lastframe then
        selected_sample.loop_start = math.floor(startpos + 0.5)
      end
      if options.endenable.value == true and endpos <= lastframe and endpos > startpos and endpos > 1 then
        selected_sample.loop_end = math.floor(endpos + 0.5)
      end
      if options.collisiontype.value > 0 then -- bounce1
        if endpos > lastframe then
          endpos = lastframe
          eflip = true
        end
        if startpos < 1  then
          startpos = 1
          sflip = true
        end
        if endpos < 2 then
          endpos = 2
          eflip = true
        end
        if startpos > endpos then 
          startpos = endpos - 1
          sflip = true
        end
        if endpos < startpos then 
          endpos = startpos + 1
          eflip = true
        end
        if (endpos - startpos) < options.minframes.value then 
          --if options.collisiontype.value == 2 then -- bounce 2 -- this is broken please do not use
          --   s = options.startspd.value 
          --   e = options.endspd.value
          --   if startpos + e < endpos + s and endpos + s > startpos + e then
          --     options.startspd.value = e
          --     options.endspd.value = s
          --   end
          --end
          if options.returntopitch.value == true then -- switch to pitch mode
            options.modetype.value = 2
            options.returntopitch.value = false
          end
          if startpos + options.minframes.value <= lastframe then
            endpos = startpos + options.minframes.value
          else
            startpos = lastframe - options.minframes.value
            endpos = lastframe
          end
          direction = options.startspd.value + options.endspd.value
          if direction > 0 then 
            if options.startspd.value > options.endspd.value then
              sflip = true
            else
              eflip = true
            end
          elseif direction < 0 then 
            if options.startspd.value < options.endspd.value then
              sflip = true
            else
              eflip = true
            end        
          end
          if direction == 0 then 
            eflip = true
            sflip = true
          end
        end
        if (startpos < 1) and (startpos + (options.startspd.value * -1) > (endpos + options.endspd.value)) then
          endpos = (startpos + options.startspd.value * -1) + options.minframes.value
          if options.endspd.value < 0 then
            eflip = true
          end
        end    
        if (endpos > lastframe) and (endpos + (options.endspd.value * -1) < (startpos + options.startspd.value)) then
          startpos = (endpos + options.endspd.value * -1) - options.minframes.value
          if options.startspd.value > 0 then
            sflip = true
          end
        end    
        if (sflip == true) then
          options.startspd.value = options.startspd.value * -1
          sflip = false      
        end
        if (eflip == true) then
          options.endspd.value = options.endspd.value * -1
          eflip = false      
        end
      end
      if options.startenable.value == true then
        startpos = startpos + options.startspd.value
      else
        options.startspd.value = 0
        startpos = selected_sample.loop_start
      end
      if options.endenable.value == true then
        endpos = endpos + options.endspd.value
      else
        options.endspd.value = 0
        endpos = selected_sample.loop_end
      end
    end
    if (options.modetype.value == 2) then -- pitch
      if (startpos > 0) and ((startpos + targetframes) < lastframe) then
        selected_sample.loop_start = math.floor(startpos + 0.5)
        selected_sample.loop_end = math.floor(startpos + targetframes + 0.5)
      end
      if (startpos < 1) then
        startpos = 1
        vflip = true
      end
      if ((startpos + targetframes) > lastframe) then
        startpos = lastframe - targetframes
        vflip = true
      end
      if (vflip == true) then
        options.speed.value = options.speed.value * -1
        vflip = false      
      end
      startpos = startpos + options.speed.value
      endpos = startpos + options.speed.value + targetframes 
    end   
    update_progress_func()
    coroutine.yield()
    lastsample = rsong.selected_sample_index
   else
     break
   end 
  end
  gui.start_stop_process()
end

function init_tool()
  rsong = renoise.song()
  selected_sample = rsong.selected_sample
  if (rsong.selected_sample ~= nil) then
    nosample = false
    originalstartpos = selected_sample.loop_start
    originalendpos = selected_sample.loop_end
    originalloopmode = selected_sample.loop_mode  
    startpos = selected_sample.loop_start
    endpos = selected_sample.loop_end
    sample_rate = selected_sample.sample_buffer.sample_rate
    lastsample = rsong.selected_sample_index
    lastframe = selected_sample.sample_buffer.number_of_frames
    originallastframe = lastframe
    if options.maxspeed.value > (lastframe / 2) then
      options.maxspeed.value = lastframe / 2
    end  
    if options.minframes.value > lastframe then
      options.minframes.value = lastframe
    end
  end
end

function create_gui()
  local loopmodes = {"OFF", "FORWARD", "REVERSE", "PING PONG"}
  local directionstrings = {"---","-->","<--","<->"}
  local dialog, process
  local vb = renoise.ViewBuilder()

  local function changereturntopitch()
    options.returntopitch.value = vb.views.rpitch.value  
  end

  local function changeminframes()
    options.minframes.value = vb.views.minf.value
    vb.views.minf_label.text = "Minimum Frames: " .. options.minframes.value
  end

  local function changemaxspeed(self)
    options.maxspeed.value = vb.views.maxspd.value
    vb.views.sspd.min = (options.maxspeed.value * -1)
    vb.views.sspd.max = options.maxspeed.value
    if options.startspd.value > options.maxspeed.value then
      options.startspd.value = options.maxspeed.value
    end
    if math.abs(options.startspd.value) > options.maxspeed.value then
      options.startspd.value = options.maxspeed.value * -1
    end
    vb.views.espd.min = (options.maxspeed.value * -1)
    vb.views.espd.max = options.maxspeed.value
    if options.endspd.value > options.maxspeed.value then
      options.endspd.value = options.maxspeed.value
    end
    if math.abs(options.endspd.value) > options.maxspeed.value then
      options.endspd.value = options.maxspeed.value * -1
    end
    vb.views.spd.min = (options.maxspeed.value * -1)
    vb.views.spd.max = options.maxspeed.value
    if options.speed.value > options.maxspeed.value then
      options.speed.value = options.maxspeed.value
    end
    if math.abs(options.speed.value) > options.maxspeed.value then
      options.speed.value = options.maxspeed.value * -1
    end
    vb.views.maxspd_label.text = "Maximum speed: " .. options.maxspeed.value
  end 

  local function changesenable()
    options.startenable.value = vb.views.senable.value
  end
  
    local function changeeenable()
    options.endenable.value = vb.views.eenable.value
  end

  local function changemode()
    options.modetype.value = math.floor(vb.views.mode.value + 0.5)
  end

  local function changepitch()
    options.thenote.value = math.floor(vb.views.pitch.value + 0.5)
    vb.views.pitch_text.text = "Note: " .. notename(options.thenote.value)
  end

  local function changespd()
    options.speed.value = vb.views.spd.value
    vb.views.spd_text.text = "Pitch speed: " .. tostring(options.speed.value) 
  end
  
  local function changesspd()
    options.startspd.value = vb.views.sspd.value
    vb.views.sspd_text.text = "Loose Start speed: " .. tostring(options.startspd.value) 
  end
  
  local function changeespd() 
    options.endspd.value = vb.views.espd.value
    vb.views.espd_text.text = "Loose End speed: " .. tostring(options.endspd.value)
  end
  
  local function changeloop()
    selected_sample.loop_mode = math.floor(vb.views.ltype.value + 0.5)
  end
  
  local function update_progress()
    if (not dialog or not dialog.visible) then
      process:stop()
      return
    end
    local targetframesstring = ""
    if options.modetype.value == 2 then
      targetframesstring = string.format("Aiming for: %d", targetframes)
    end
    vb.views.minf.value = options.minframes.value
    vb.views.maxspd.value = options.maxspeed.value
    vb.views.mode.value = options.modetype.value 
    vb.views.sspd.value = options.startspd.value
    vb.views.espd.value = options.endspd.value
    vb.views.ltype.value = selected_sample.loop_mode
    vb.views.spd.value = options.speed.value
    vb.views.pitch.value = options.thenote.value
    vb.views.rpitch.value  = options.returntopitch.value
    vb.views.progress_text.text = string.format(
    "%d %s %d    %s", startpos, directionstrings[selected_sample.loop_mode], endpos, targetframesstring)
  end

  local function start_stop_process(self)
    if (not process or not process:running()) then
      vb.views.start_button.text = "Stop"
      nosample = true
      init_tool()
      if nosample == false then
        process = ProcessSlicer(main, update_progress)
        process:start()
      else
        vb.views.start_button.text = "Start"
        vb.views.progress_text.text = ""
      end 
    elseif (process and process:running()) then
      vb.views.start_button.text = "Start"
      vb.views.progress_text.text = ""
      process:stop()
    end
  end

  ---- process GUI

  local DEFAULT_DIALOG_MARGIN = 
    renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN
  
  local DEFAULT_CONTROL_SPACING = 
    renoise.ViewBuilder.DEFAULT_CONTROL_SPACING
  
  local DEFAULT_DIALOG_BUTTON_HEIGHT = 
    renoise.ViewBuilder.DEFAULT_DIALOG_BUTTON_HEIGHT
  
  local dialog_content = vb:column { 
   uniform = false,
   margin = DEFAULT_DIALOG_MARGIN,
   spacing = DEFAULT_CONTROL_SPACING,
   vb:horizontal_aligner { mode = "center",
    vb:vertical_aligner { mode = "center",
      vb:column {     
        vb:horizontal_aligner { mode = "center", 
          vb:column {
            vb:text {
              id = "progress_text",
              text = ""
            },
            vb:button {
              id = "start_button",
              text = "Start",
              height = DEFAULT_DIALOG_BUTTON_HEIGHT,
              width = 256,
              height = 25,
              notifier = start_stop_process,
              midi_mapping = "ModLoop:ToggleStart"
            },
            vb:space { height = 10 }, 
            vb:switch {
              id = "mode",
              items = { "Loose", "Pitch" },
              value = options.modetype.value,
              width = 256,
              height = 25,
              notifier = changemode,
              midi_mapping = "ModLoop:Mode"
            },
            vb:switch {
              id = "ltype",
              width = 256,
              height = 25,
              items = {"OFF", "FORWARD", "REVERSE", "PING PONG"},
              value = selected_sample.loop_mode,
              notifier = changeloop,
              midi_mapping = "ModLoop:LoopMode"
            },
            vb:space { height = 10 },
            vb:slider {
              id = "maxspd",
              width = 256,
              height = 25,
              min = 1,
              max = options.maxmaxspeed.value,
              value = options.maxspeed.value,
              notifier = changemaxspeed,
              midi_mapping = "ModLoop:Maxspeed"
            },
            vb:text {
              id = "maxspd_label",
              text = "Maximum speed:" .. options.maxspeed.value
            },
            vb:space { height = 10 },
            vb:horizontal_aligner { mode = "center", 
              vb:text {
                id = "loose_label",
                text = "--- Loose Options ---"
              }
            },
            vb:slider {
              id = "minf",
              width = 256,
              height = 25,
              min = 1,
              max = options.maxminframes.value,
              value = options.minframes.value,
              notifier = changeminframes,
              midi_mapping = "ModLoop:MinFrames"
             },
            vb:text {
              id = "minf_label",
              text = "Minimum Frames: " .. options.minframes.value 
            },
            vb:row {
              vb:checkbox {
                id = "rpitch",
                value = options.returntopitch.value,
                notifier = changereturntopitch,
                midi_mapping = "ModLoop:ReturnToPitch"
              },
              vb:text {
                id = "rpitch_label",
                text = "Return to pitch mode on min frames"
              }
            },  
            vb:row {
              vb:slider {
                id = "sspd",
                width = 231,
                height = 25,
                min = (options.maxspeed.value * -1),
                max = options.maxspeed.value,
                value = options.startspd.value,
                notifier = changesspd,
                midi_mapping = "ModLoop:LooseStartspeed"
              },
              vb:vertical_aligner { mode = "center",
                vb:checkbox {
                  id = "senable",
                  value = options.startenable.value,
                  notifier = changesenable,
                  midi_mapping = "ModLoop:StartEnable"
                }
              }
            },   
            vb:text {
              id = "sspd_text",
              text = "Loose Start speed: " .. tostring(options.startspd.value)
            },
            vb:row {
              vb:slider {
                id = "espd",
                width = 231,
                height = 25,
                min = (options.maxspeed.value * -1),
                max = options.maxspeed.value,
                value = options.endspd.value,
                notifier = changeespd,
                midi_mapping = "ModLoop:LooseEndspeed"
              },
              vb:vertical_aligner { mode = "center",
                vb:checkbox {
                  id = "eenable",
                  value = options.endenable.value,
                  notifier = changeeenable,
                  midi_mapping = "ModLoop:EndEnable"
                }
              }  
            }, 
            vb:text {
              id = "espd_text",
              text = "Loose End speed: " .. tostring(options.endspd.value)
            },
            vb:space { height = 10 },
            vb:horizontal_aligner { mode = "center",
              vb:text {
                id = "pitch_label",
                text = "--- Pitch Options ---"
              }
            },  
            vb:slider {
              id = "spd",
              width = 256,
              height = 25,
              min = (options.maxspeed.value * -1),
              max = options.maxspeed.value,
              value = options.speed.value,
              notifier = changespd,
              midi_mapping = "ModLoop:Pitchspeed"
            },
            vb:text {
              id = "spd_text",
              text = "Pitch speed: " .. tostring(options.speed.value)
            },
            vb:slider {
              id = "pitch",
              width = 256,
              height = 25,
              min = 21,
              max = 107,
              value = options.thenote.value,
              notifier = changepitch,
              midi_mapping = "ModLoop:Note"
            },
            vb:text {
              id = "pitch_text",
              text = "Note: " .. notename(options.thenote.value)
            }
          }
        }
      }
    }
  }
 }  
 dialog = renoise.app():show_custom_dialog("ModLoop v0.23", dialog_content)
 return {start_stop_process=start_stop_process}
end

renoise.tool().preferences = options
options.collisiontype.value = 3


renoise.tool():add_menu_entry{
  name = "Main Menu:Tools:ModLoop v0.23",
  invoke = function()
    init_tool()
    if (nosample == false) then
      gui = create_gui()
    end
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:ToggleStart",
  invoke = function(midi_message)
    if midi_message.int_value == 127 or midi_message.int_value == 0 then
      gui.start_stop_process()
    end
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:Mode",
  invoke = function(midi_message)
    if midi_message.int_value > 63 then
      options.modetype.value = 1
    else
      options.modetype.value = 2
    end
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:StartEnable",
  invoke = function(midi_message)
    if midi_message.int_value > 63 then
      options.startenable.value = true
    else
      options.startenable.value = false
    end
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:EndEnable",
  invoke = function(midi_message)
    if midi_message.int_value > 63 then
      options.endenable.value = true
    else
      options.endenable.value = false
    end
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:ReturnToPitch",
  invoke = function(midi_message)
    if midi_message.int_value > 63 then
      options.returntopitch.value = true
    else
      options.returntopitch.value = false
    end
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:MinFrames",
  invoke = function(midi_message)
    options.minframes.value =  (options.maxminframes.value / 128) * midi_message.int_value
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:Maxspeed",
  invoke = function(midi_message)
    options.maxspeed.value = (options.maxmaxspeed.value / 128) * midi_message.int_value
  end
}



renoise.tool():add_midi_mapping{
  name = "ModLoop:LooseStartspeed",
  invoke = function(midi_message)
    options.startspd.value = (midi_message.int_value - 64) * (options.maxspeed.value / 64)  
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:LooseEndspeed",
  invoke = function(midi_message)
    options.endspd.value = (midi_message.int_value - 64) * (options.maxspeed.value / 64)  
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:LoopMode",
  invoke = function(midi_message)
    selected_sample.loop_mode = math.floor(((midi_message.int_value+1)/32) + 0.5)  
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:Pitchspeed",
  invoke = function(midi_message)
    options.speed.value = (midi_message.int_value - 64) * (options.maxspeed.value / 64)   
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:Note",
  invoke = function(midi_message)
    options.thenote.value = midi_message.int_value   
  end
}

