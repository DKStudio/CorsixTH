--[[ Copyright (c) 2010 Sjors Gielen

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE. --]]

dofile "dialogs/fullscreen"

--! Town map fullscreen window (purchase land, set radiator levels, map overview).
class "UITownMap" (UIFullscreen)

function UITownMap:UITownMap(ui)
  self:UIFullscreen(ui)

  local app      = self.ui.app
  local hospital = self.ui.hospital
  local gfx      = app.gfx

  local palette   = gfx:loadPalette("QData", "Town01V.pal")
  palette:setEntry(255, 0xFF, 0x00, 0xFF) -- Make index 255 transparent

  self.background = gfx:loadRaw("Town01V", 640, 480)
  self.info_font  = gfx:loadFont("QData", "Font34V", false, palette)
  self.city_font = gfx:loadFont("QData", "Font31V", false, palette)
  self.money_font = gfx:loadFont("QData", "Font05V")
  self.panel_sprites = gfx:loadSpriteTable("QData", "Town02V", true, palette)
  
  self.default_button_sound = "selectx.wav"
  self.default_buy_sound    = "buy.wav"

  -- config is a *runtime* configuration list; re-instantiations of the dialog
  -- share the same values, but it's not saved across saves or sessions
  local config   = app.runtime_config.town_dialog
  if config == nil then
    config = {}
    app.runtime_config.town_dialog = config
    config.people_enabled = true
    config.plants_enabled = true
    config.fire_ext_enabled = true
    config.objects_enabled = true
    config.radiators_enabled = true  
  end

  -- A list of areas in the town, including the owner.
  -- In single player there are only bought and available areas, in multiplayer
  -- areas are owned by players and when a player wants to buy a piece of
  -- terrain, an auction is started.
  -- TODO display the areas, in the right color
  -- TODO display everything in the areas
  -- TODO make it possible to buy areas
  -- TODO multiplayer mode
  
  -- Quit and image alter buttons
  -- addPanel( imgid, x, y )
  -- makeButton( x, y, w, h, imgid, callback[, callback_self[, right_callback])
  -- it looks like the image you give to addPanel is the default image; the
  -- image given to makeButton is the override image.
  self:addPanel(9, 30,  420):makeButton(0, 0, 200, 50, 0, self.bankManager,
  -- right click on this $ sign closes the dialog
    nil, self.close)
  self:addPanel(0, 594, 437):makeButton(0, 0, 26, 26, 8, self.close)
  self:addPanel(0, 171, 315):makeButton(0, 0, 20, 20, 6, self.increaseHeat)
  self:addPanel(0, 70,  314):makeButton(0, 0, 20, 20, 7, self.decreaseHeat)

  -- add the toggle buttons
  local function toggle_button(sprite, x, y, option)
    local panel = self:addPanel(sprite, x, y)
    local btn = panel:makeToggleButton(0, 0, 46, 46, 0, --[[persistable:town_map_config_button]] function(state)
      app.runtime_config.town_dialog[option] = state
    end)
    btn:setToggleState(config[option])
  end
  toggle_button(1, 140,  37, "people_enabled")
  toggle_button(2, 140,  89, "plants_enabled")
  toggle_button(3, 140, 141, "fire_ext_enabled")
  toggle_button(4, 140, 193, "objects_enabled")
  toggle_button(5, 140, 246, "radiators_enabled")
end

-- temporary, remove later
-- because currently we don't know what ID's are objects, we have to print
-- every unknown object to decide whether it is counted as an object in the
-- town map or not.
-- TODO add this as a property in the item itself (is_object_in_town_map?)
local known_ids = { "cabinet", "chair", "desk", "extinguisher", "bin",
                    "radiator", "plant", "bench", "entrance_left_door",
                    "entrance_right_door" }
function UITownMap:is_unknown_id(id)
  for i = 1, #known_ids do
    if( id == known_ids[i] ) then
      return false
    end
  end
  return true
end

function UITownMap:close()
  self.ui:disableKeyboardRepeat()
  Window.close(self)
end

function UITownMap:draw(canvas, x, y)
  self.background:draw(canvas, self.x + x, self.y + y)
  UIFullscreen.draw(self, canvas, x, y)
  
  x, y = self.x + x, self.y + y
  local app      = self.ui.app
  local hospital = self.ui.hospital
  local world    = hospital.world
  -- config is a *runtime* configuration list; re-instantiations of the dialog
  -- share the same values, but it's not saved across saves or sessions
  local config   = app.runtime_config.town_dialog
  
  -- We need to draw number of people, plants, fire extinguisers, other objects
  -- and radiators, heat level and radiator total costs, to the left.
  -- The number of patients, for some reason, is always 1 too much in the
  -- original game (it actually starts with 1). CorsixTH currently mimics this
  -- behaviour, but this can be changed later.
  local patientcount = 1
  local plants = 0
  local fireext = 0
  local objs = 0
  local radiators = 0

  -- Even though it says "people", staff and guests like VIPS aren't included.
  -- TH counts someone as a patient the moment he walks into the hospital; when
  -- he walks out to really go away, he isn't counted anymore.
  for _, patient in pairs(hospital.patients) do
    -- only count patients that are in the hospital
    if hospital:isInHospital(patient.tile_x, patient.tile_y) then
      patientcount = patientcount + 1
    end
  end

  -- a silly loop that checks every tile in the map for countable objects.
  -- TODO: we probably want to limit this to just check all corridor and room
  -- objects, that should be traversable in a much quicker and more efficient
  -- way.
  for x = 0, world.map.width-1 do
    for y = 0, world.map.height-1 do
      local l_objects = world:getObjects(x, y)
      if l_objects ~= nil then
        for i = 1, #l_objects do
          local object_type = l_objects[i]["object_type"].id

          if object_type == "desk" then
            objs = objs + 1
          elseif object_type == "extinguisher" then
            fireext = fireext + 1
          elseif object_type == "radiator" then
            radiators = radiators + 1
          elseif object_type == "plant" then
            plants = plants + 1
          end

          -- TODO remove once we "know" all object ID's, or can detect whether
          -- an item is an object in the town map (@see is_unknown_id())
          if self:is_unknown_id(object_type) then
            for key, value in pairs(l_objects[i]) do
              if key == "object_type" then
                for key2, value2 in pairs(value) do
                  print(x, y, i, key, key2, value2)
                end
              else
                print(x, y, i, key, value)
              end
            end
          end
        end
      end
    end
  end

  self.info_font:draw(canvas, patientcount, x +  95, y +  57)
  self.info_font:draw(canvas, plants,       x +  95, y + 110)
  self.info_font:draw(canvas, fireext,      x +  95, y + 157)
  self.info_font:draw(canvas, objs,         x +  95, y + 211)
  self.info_font:draw(canvas, radiators,    x +  95, y + 265)
  -- TODO how is radiator cost computed?
  self.info_font:draw(canvas, "0",          x + 100, y + 355)
  
  -- draw money balance
  self.money_font:draw(canvas, ("%7i"):format(hospital.balance), x + 49, y + 431)

  -- radiator heat
  local rad_max_width = 60 -- Radiator indicator width
  local rad_width = rad_max_width * hospital.radiator_heat
  for dx = 0, rad_width do
    self.panel_sprites:draw(canvas, 9, x + 101 + dx, y + 319)
  end

  -- city name
  self.city_font:draw(canvas, world.level_name, x + 390, y + 45)

  -- plots
  self.city_font:draw(canvas, "Plots are TODO!", x + 380, y + 200)

  -- plot number, owner, area and price
  self.city_font:draw(canvas, "Plot Number", x + 227, y + 435)
  self.city_font:draw(canvas, ":",           x + 300, y + 435)
  self.city_font:draw(canvas, "-",           x + 315, y + 435)
  self.city_font:draw(canvas, "Plot Owner ", x + 227, y + 450)
  self.city_font:draw(canvas, ":",           x + 300, y + 450)
  self.city_font:draw(canvas, "-",           x + 315, y + 450)
  self.city_font:draw(canvas, "Plot Area  ", x + 432, y + 435)
  self.city_font:draw(canvas, ":",           x + 495, y + 435)
  self.city_font:draw(canvas, "-",           x + 515, y + 435)
  self.city_font:draw(canvas, "Plot Price ", x + 432, y + 450)
  self.city_font:draw(canvas, ":",           x + 495, y + 450)
  self.city_font:draw(canvas, "-",           x + 515, y + 450)
end

function UIBottomPanel:dialogBankManager()
  local dlg = UIBankManager(self.ui)
  self.ui:addWindow(dlg)
end

function UITownMap:decreaseHeat()
  local h = self.ui.hospital
  local heat = math.floor(h.radiator_heat * 10 + 0.5)
  heat = heat - 1
  if heat < 1 then
    heat = 1
  end
  h.radiator_heat = heat / 10
end

function UITownMap:increaseHeat()
  local h = self.ui.hospital
  local heat = math.floor(h.radiator_heat * 10 + 0.5)
  heat = heat + 1
  if heat > 10 then
    heat = 10
  end
  h.radiator_heat = heat / 10
end