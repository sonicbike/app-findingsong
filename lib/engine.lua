-- Swamp Bike Opera embedded system for Kaffe Matthews
-- Copyright (C) 2012 Wolfgang Hauptfleisch, Dave Griffiths
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

module("engine", package.seeall)

require 'gps'
require 'posix'
require 'poly'
require 'map'
require 'direction'
require 'random'
require 'audioc'
require 'socket'

----------------------------------------------------------------
local directionstate

-- override for zones

overrides = {
--   ["big"]={
--      colour="blue",
--      name="directional",
--      dir="e",
--   },
}

----------------------------------------------------------------

function gpslog(lat, lon)
   local  file = io.open(CONFIG.gpslog, "a")
   local logmessage = os.date().." "..lat.." "..lon.."\n"
   file:write(logmessage)
   file:close()
end

function log(logmessage)
   print(os.date().." "..logmessage)

   local  file = io.open(CONFIG.logfile, "a")
   local logmessage = os.date().." "..logmessage.."\n"
   file:write(logmessage)
   file:close()
end

function say(txt)
    if txt~="" then
        print("saying:"..txt)
        --os.execute("espeak \""..txt.."\"")
    end
end

----------------------------------------------------------------

function read_events(events)
    local txt="";

    for k,layer in pairs(events) do
        for k,event in pairs(layer) do
            txt=txt.." "..event.type.." ".." "..event.zone_colour.." "..
                     event.zone_name.." in "..event.layer_name.."."
    end
    end
    say(txt)
end

----------------------------------------------------------------

function dispatch_override(event,pos_state,override)
    if override.name=="directional" then
        play_directional(event,pos_state,override)
    end
end

----------------------------------------------------------------

function play_directional(event,pos_state,override)
    --utils.table_print(override)

    --print(direction.pan_from(pos_state.dir,override.dir))

    if event.type=="entered-zone" then
--       print(direction.resolve(poly.angle(pos_state.dir)))
--       utils.table_print(pos_state.dir)
--       print(override.dir)
       audioc.loop(event.zone_name,
                   direction.pan_from(pos_state.dir,override.dir))
    end
    if event.type=="left-zone" then
       audioc.stop(event.zone_name)
    end
end

--
--          n
--        nw ne
--       w     e
--        sw se
--          s
--

-- return true if facing in same direction (with 90 deg tolerance)
-- this is stupid and dumb version
function direction_compare(one,two)
    if (one == "n") then
       return utils.find_value(two,{"n","nw","n","ne","e"});
    end
    if (one == "ne") then
       return utils.find_value(two,{"nw","n","ne","e","se"});
    end
    if (one == "e") then
       return utils.find_value(two,{"n","ne","e","se","s"});
    end
    if (one == "se") then
       return utils.find_value(two,{"ne","e","se","s","sw"});
    end
    if (one == "s") then
       return utils.find_value(two,{"e","se","s","sw","w"});
    end
    if (one == "sw") then
       return utils.find_value(two,{"se","s","sw","w","nw"});
    end
    if (one == "w") then
       return utils.find_value(two,{"s","sw","w","nw","n"});
    end
    if (one == "nw") then
       return utils.find_value(two,{"sw","w","nw","n","ne"});
    end
    return false
end


function cats_to_direction(parent,cats)
    if (utils.find_value(parent..":North",cats)) then
        if (utils.find_value(parent..":East",cats)) then
        return "ne"
        end
        if (utils.find_value(parent..":West",cats)) then
        return "nw"
        end
    return "n"
    end
    if (utils.find_value(parent..":South",cats)) then
        if (utils.find_value(parent..":East",cats)) then
        return "se"
        end
        if (utils.find_value(parent..":West",cats)) then
        return "sw"
        end
    return "s"
    end
    if (utils.find_value(parent..":West",cats)) then
        return "w"
    end
    if (utils.find_value(parent..":East",cats)) then
        return "e"
    end
    return "centre";
end

function range(maxA, minA, maxB, minB, valA)
    rangeA = maxA-minA
    rangeB = maxB-minB  
    valueB = (((valA-minA)*rangeB)/rangeA)+minB
    return valueB 
end

function whats_my_pitch(direction, speed)
    mode = CONFIG.pitch_mode
    print("pitch_mode: "..mode)
    -- Experiment: Pitch tied to speed
    if mode == "pitch-speed" then
        if speed > 0.01 then
            speed = 0.01
        end
        maxA = 1.0
        minA = 0
        maxB = 2.0
        minB = 0.2
        setpitch = range(maxA, minA, maxB, minB, speed)
        --print("lib/engin.lua Pitch:"..setpitch..' Speed:'..speed)
        return setpitch
    end
    -- Experiment: Random pitch
    if mode == "pitch-random" then
        return math.random(10)*0.2
    end 
    -- Experiment: Pitch tied to direction
    if mode == "pitch-direction" then
        if (direction == "n") then
        return 1
        end
        if (direction == "ne") then
        return 2
        end
        if (direction == "e") then
        return 2
        end
        if (direction == "se") then
        return 2
        end
        if (direction == "s") then
        return 1
        end
        if (direction == "sw") then
        return 0.2
        end
        if (direction == "w") then
        return 0.2
        end
        if (direction == "nw") then
        return 0.2
        end
    end
    return 1
end

----------------------------------------------------------------
-- not sure this is the best place for this!
local panned_samples={}
local one_shot_samples={}
local pitch_change_samples={} -- samples change pitch on change of direction

function play_events(events,pos_state)
    
    -- first if the direction has been updated, go through
    if pos_state.new_direction then
        --print("updating direction")
        -- all the panned samples
        for name,dir in pairs(panned_samples) do
            local pan=direction.pan_from(pos_state.dir,dir)
            print("shifting "..name.." to "..pan)
            audioc.shift(name,pan)
        end
        -- all the samples to be pitch changed
        for name,dir in pairs(pitch_change_samples) do
            print("Change pitch of:"..name.." Direction:"..directionstate.direction.. " Speed:"..pos_state.speed)
            newpitch = whats_my_pitch(directionstate.direction, pos_state.speed)
            audioc.pitch(name,newpitch)
        end

    end

    -- now look through all the maps for new events
    for k,layer in pairs(events) do
       
        for k,event in pairs(layer) do
            engine.log(event.type.." "..event.zone_name.." in "..event.layer_name)
            -- Setup some vars
            local switch_dir = cats_to_direction("Direction Parameter",event.zone_categories)
            local heading = direction.resolve(poly.angle(pos_state.dir))
            local name=event.zone_name
            -- Pitch stuff - does the zoen support pitch change on change of direction?
            if (utils.find_value("Sample Parameters:Pitch",event.zone_categories)) then
                print("Enable pitch change for: "..name)
                pitch_change_samples[name]=switch_dir..'|'..heading
            end
            -- Directional stuff
            if (switch_dir~="centre") then
                -- if this zone is using a direction to switch, check here
                print("DIRECTIONAL--->"..switch_dir.." vs current "..heading)
                if (direction_compare(switch_dir,heading)) then
                        print "ACCEPTED"
                else
                    print "wrong way"
                end
            end

            if switch_dir=="centre" or direction_compare(switch_dir,heading) then    
                -- defaults
                local name=event.zone_name
                local loop="no"
                if (utils.find_value("Sample Parameters:Loop",event.zone_categories)) then
                    loop="yes"
                end
                local dir=cats_to_direction("Pan Parameter",event.zone_categories)
                -- is it a one shot sample?
                if (utils.find_value("Sample Parameters:One shot",event.zone_categories)) then
                    one_shot_samples[name]="yes"
                    --print('engine.lua found one shot:'..name)
                    audioc.isoneshot(name)
                end

                -- look for an override
                local override=overrides[event.zone_name]
                if override then
                    print("engin.lua dispatch override: name:"..name..' loop:'..loop..' dir:'..dir )
                    dispatch_override(event,pos_state,override)
                else
                    -- default behaviour
                    if event.type=="entered-zone" then
                        if dir=="centre" then ----- normal -------
                            if loop=="no" then
                                --print("engin.lua play once: name:"..name..' loop:'..loop..' dir:'..dir )
                                audioc.play(name)
                            else
                                --print("engin.lua play and loop: name:"..name..' loop:'..loop..' dir:'..dir )
                                audioc.loop(name)
                            end
                        else ------- directional ---------------
                            -- add to panned samples so we can update it later
                            panned_samples[name]=dir
                            --print("added panned "..name.." "..dir)
                            local pan=direction.pan_from(pos_state.dir,dir)
                            if loop=="no" then
                                audioc.play(name,pan)
                            else
                                audioc.loop(name,pan)
                            end
                        end
                    end
                end

                if event.type=="left-zone" then
                    if panned_samples[name] then
                        panned_samples[name]=nil
                    end
                    if one_shot_samples[name]~="yes" then
                        print('engin.lua left-zone fadeout sample:'..name)
                        audioc.fadeout(name)
                    else
                        print('engin.lua left-zone leave one shot playing:'..name)
                    end
                end

            end
        end
    end
end

----------------------------------------------------------------------

function update_pos_state(pos,state)
    -- calculate distance since last time
    local time_diff = os.time() - state.time

    state.new_direction=false

    if time_diff > CONFIG.direction_track_time then
        state.time = os.time()
        if state.pos then
            local distance=poly.distance_km(pos.lat, pos.lng,state.pos.lat, state.pos.lng);
            state.speed=distance/CONFIG.direction_track_time;
            state.dir={lat=pos.lat-state.pos.lat,lng=pos.lng-state.pos.lng}
        end
        state.pos = pos
        state.new_direction=true
        state.direction = direction.resolve(poly.angle(state.dir))
        --log("speed is "..state.speed.."km/h".." direction is "..state.direction)
        --print("speed is "..state.speed.."km/h".." direction is "..state.direction)
    end
    directionstate = state
    return state
end

----------------------------------------------------------------

function load_events(events,pos_state)
    for k,layer in pairs(events) do
        for k,event in pairs(layer) do
            engine.log("load event: "..event.type.." "..event.zone_name.." in "..event.layer_name)
            -- zone name consists of:
            -- <name>_<loop>_<direction>_<ghost>
            local tokens=std.split(event.zone_name,"_")
            -- defaults
            local name=tokens[1]
            -- default behaviour
            if event.type=="entered-zone" then
                audioc.load(name)
            end
            if event.type=="left-zone" then
                audioc.unload(name)
            end
        end
    end
end
