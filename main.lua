--[[============================================================================
main.lua
============================================================================]]--

--[[

This is an experiment to modify sample loop positions by bonafide@martica.org
portions of this code for handling notes and frequencies, although slightly modified are from:
https://github.com/MightyPirates/OpenComputers/blob/master-MC1.7.10/src/main/resources/assets/opencomputers/loot/openos/lib/note.lua

ToDo:

- possibly handle the pitch changes caused by high velocity loop directions
- possibly copy a little bit of the sample buffer to make a judgement about zero crossings
- glide back to note from loose mode
- other ways of modifying the loop (random locations? octave slider? etc)
- gracefully restore the previous loop points and loopmode on exit or selected_sample change

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
  maxvelocity = 512,
  startvel = 10,
  endvel = 20,
  minframes = 1, 
  velocity = 128, 
  thenote = 48,
  modetype = 2
}

startpos = nil
endpos = nil
loopmode = nil
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
  while true do 
   if (rsong.selected_sample ~= nil) then
      nosample = false
    if (lastsample ~= rsong.selected_sample_index) then
      selected_sample = rsong.selected_sample
      startpos = selected_sample.loop_start
      endpos = selected_sample.loop_end
      sample_rate = selected_sample.sample_buffer.sample_rate
    end  
    lastframe = selected_sample.sample_buffer.number_of_frames
    onecycle = 1/notefreq(options.thenote.value)
    targetframes = onecycle * sample_rate
    
    -- Here begins the logic for actually moving the loop points around...
    --
    -- 1 - loose   - the start and end points move back and forth with unique velocities
    -- 2 - pitch   - the start and end points move together in order to create a pitch
    -- 3 - ?????
  
    if (options.modetype.value == 1) then -- loose
      if startpos > 0 and startpos < endpos and startpos < lastframe then
        selected_sample.loop_start = math.floor(startpos + 0.5)
      end
      if endpos <= lastframe and endpos > startpos and endpos > 0 then
        selected_sample.loop_end = math.floor(endpos + 0.5)
      end
      if endpos > lastframe then
        endpos = lastframe
        eflip = true
      end
      if endpos < 1 then 
        endpos = startpos + 1
        eflip = true
      end
      if startpos < 0  then
        startpos = 1
        sflip = true
      end
      if startpos > lastframe then 
        startpos = endpos - 1
        sflip = true
      end
      if (endpos - startpos) < options.minframes.value then 
        if startpos + options.minframes.value <= lastframe then
          endpos = startpos + options.minframes.value
        end
        direction = options.startvel.value + options.endvel.value
        if direction > 0 then 
          if options.startvel.value > options.endvel.value then
            sflip = true
          else
            eflip = true
          end
        elseif direction < 0 then 
          if options.startvel.value < options.endvel.value then
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
      if (sflip == true) then
        options.startvel.value = options.startvel.value * -1
        sflip = false      
      end
      if (eflip == true) then
        options.endvel.value = options.endvel.value * -1
        eflip = false      
      end
      startpos = startpos + options.startvel.value
      endpos = endpos + options.endvel.value
    end
    if (options.modetype.value == 2) then -- pitch
      if (startpos > 0) and ((startpos + targetframes) < lastframe) then
        selected_sample.loop_start = math.floor(startpos + 0.5)
        selected_sample.loop_end = math.floor(startpos + targetframes + 0.5)
      end
      if (startpos < 0) then
        startpos = 1
        vflip = true
      end
      if ((startpos + targetframes) > lastframe) then
        startpos = lastframe - targetframes
        vflip = true
      end
      if (vflip == true) then
        options.velocity.value = options.velocity.value * -1
        vflip = false      
      end
      startpos = startpos + options.velocity.value
      endpos = startpos + options.velocity.value + targetframes -- for graceful switching back to loose mode
    end   
    update_progress_func()
    coroutine.yield()
    lastsample = rsong.selected_sample_index
   else
     nosample = true
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
    startpos = selected_sample.loop_start
    endpos = selected_sample.loop_end
    sample_rate = selected_sample.sample_buffer.sample_rate
    lastsample = rsong.selected_sample_index
  end
end

function create_gui()
  local loopmodes = {"OFF", "FORWARD", "REVERSE", "PING PONG"}
  local dialog, process
  local vb = renoise.ViewBuilder()

  local function changemode()
    options.modetype.value = math.floor(vb.views.mode.value + 0.5)
  end

  local function changepitch()
    options.thenote.value = math.floor(vb.views.pitch.value + 0.5)
    vb.views.pitch_text.text = "Note: " .. notename(options.thenote.value)
  end

  local function changevel()
    options.velocity.value = vb.views.vel.value
    vb.views.vel_text.text = "Pitch velocity: " .. tostring(options.velocity.value) 
  end
  
  local function changesvel()
    options.startvel.value = vb.views.svel.value
    vb.views.svel_text.text = "Loose Start velocity: " .. tostring(options.startvel.value) 
  end
  
  local function changeevel() 
    options.endvel.value = vb.views.evel.value
    vb.views.evel_text.text = "Loose End velocity: " .. tostring(options.endvel.value)
  end
  
  local function changeloop()
    selected_sample.loop_mode = math.floor(vb.views.ltype.value + 0.5)
  end
  
  local function update_progress()
    if (not dialog or not dialog.visible) then
      process:stop()
      return
    end
    vb.views.mode.value = options.modetype.value 
    vb.views.svel.value = options.startvel.value
    vb.views.evel.value = options.endvel.value
    vb.views.ltype.value = selected_sample.loop_mode
    vb.views.vel.value = options.velocity.value
    vb.views.pitch.value = options.thenote.value
    vb.views.progress_text.text = string.format(
    "%d <-> %d      Aiming for: %d", startpos, endpos, targetframes)
  end

  local function start_stop_process(self)
    if (not process or not process:running()) then
      vb.views.start_button.text = "Stop"
      process = ProcessSlicer(main, update_progress)
      process:start()
    elseif (process and process:running()) then
      vb.views.start_button.text = "Start"
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
    vb:vertical_aligner { mode = "center",    
      vb:horizontal_aligner { width = 300, mode = "center", 
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
            midi_mapping = "ModLoop:toggle_start"
          },
          vb:switch {
            id = "mode",
            items = { "Loose", "Pitch" },
            value = options.modetype.value,
            width = 256,
            height = 25,
            notifier = changemode,
            midi_mapping = "ModLoop:mode"
          }
        }
      },   
      vb:horizontal_aligner { width = 300, mode = "center",
        vb:column {
          vb:slider {
            id = "svel",
            width = 256,
            height = 25,
            min = (options.maxvelocity.value * -1),
            max = options.maxvelocity.value,
            value = options.startvel.value,
            notifier = changesvel,
            midi_mapping = "ModLoop:LooseStartVelocity"
          }, 
          vb:text {
            id = "svel_text",
            text = "Loose Start options.velocity: " .. tostring(options.startvel.value)
          },
          vb:slider {
            id = "evel",
            width = 256,
            height = 25,
            min = (options.maxvelocity.value * -1),
            max = options.maxvelocity.value,
            value = options.endvel.value,
            notifier = changeevel,
            midi_mapping = "ModLoop:LooseEndVelocity"
          },
          vb:text {
            id = "evel_text",
            text = "Loose End options.velocity: " .. tostring(options.endvel.value)
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
          vb:slider {
            id = "vel",
            width = 256,
            height = 25,
            min = (options.maxvelocity.value * -1),
            max = options.maxvelocity.value,
            value = options.velocity.value,
            notifier = changevel,
            midi_mapping = "ModLoop:PitchVelocity"
          },
          vb:text {
            id = "vel_text",
            text = "Pitch Velocity: " .. tostring(options.velocity.value)
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
  dialog = renoise.app():show_custom_dialog("ModLoop v0.1", dialog_content)
  return {start_stop_process=start_stop_process}
end

renoise.tool().preferences = options

renoise.tool():add_menu_entry{
  name = "Main Menu:Tools:ModLoop v0.1",
  invoke = function()
    init_tool()
    if (nosample == false) then
      gui = create_gui()
    end
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:toggle_start",
  invoke = function(midi_message)
    if midi_message.int_value == 127 or midi_message.int_value == 0 then
      gui.start_stop_process()
    end
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:mode",
  invoke = function(midi_message)
    if midi_message.int_value > 63 then
      options.modetype.value = 1
    else
      options.modetype.value = 2
    end
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:LooseStartVelocity",
  invoke = function(midi_message)
    svel = (midi_message.int_value - 64) * (options.maxvelocity.value / 64)  
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:LooseEndVelocity",
  invoke = function(midi_message)
    evel = (midi_message.int_value - 64) * (options.maxvelocity.value / 64)  
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:LoopMode",
  invoke = function(midi_message)
    selected_sample.loop_mode = math.floor(((midi_message.int_value+1)/32) + 0.5)  
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:PitchVelocity",
  invoke = function(midi_message)
    options.velocity.value = (midi_message.int_value - 64) * (options.maxvelocity.value / 64)   
  end
}

renoise.tool():add_midi_mapping{
  name = "ModLoop:Note",
  invoke = function(midi_message)
    options.thenote.value = midi_message.int_value   
  end
}

