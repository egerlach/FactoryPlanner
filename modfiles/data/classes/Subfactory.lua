-- 'Class' representing a independent part of the factory with in- and outputs
Subfactory = {}

function Subfactory.init(name, icon, timescale_setting)
    local timescale_to_number = {one_second = 1, one_minute = 60, one_hour = 3600}

    local subfactory = {
        name = name,
        icon = nil,
        timescale = timescale_to_number[timescale_setting],
        energy_consumption = 0,
        pollution = 0,
        notes = "",
        mining_productivity = nil,
        Product = Collection.init(),
        Byproduct = Collection.init(),
        Ingredient = Collection.init(),
        Floor = Collection.init(),
        selected_floor = nil,
        scopes = {},
        valid = true,
        mod_version = global.mod_version,
        class = "Subfactory"
    }

    Subfactory.set_icon(subfactory, icon)

    -- Add first floor to the subfactory
    subfactory.selected_floor = Floor.init(nil)
    Subfactory.add(subfactory, subfactory.selected_floor)

    return subfactory
end


-- Exceptionally, a setter method to centralize edge-case handling
function Subfactory.set_icon(subfactory, icon)
    if icon ~= nil and icon.type == "virtual" then icon.type = "virtual-signal" end
    subfactory.icon = icon
end

-- Gets the scope by the given name, or a default state
function Subfactory.get_scope(self, name, raw)
    if self.scopes == nil then self.scopes = {} end
    self.scopes[name] = self.scopes[name] or "left"
    if raw then return self.scopes[name]
    else return ((self.scopes[name] == "left") and "Subfactory" or "Floor") end
end

-- Sets the given scope by to the given state
function Subfactory.set_scope(self, name, state)
    if self.scopes == nil then self.scopes = {} end
    self.scopes[name] = state
end


function Subfactory.add(self, object)
    object.parent = self
    return Collection.add(self[object.class], object)
end

function Subfactory.remove(self, dataset)
    -- Removes all subfloors of a Floor to avoid orphanism
    if dataset.class == "Floor" then
        Floor.remove_subfloors(dataset)
    end

    return Collection.remove(self[dataset.class], dataset)
end

function Subfactory.get(self, class, dataset_id)
    return Collection.get(self[class], dataset_id)
end

function Subfactory.get_in_order(self, class, reverse)
    return Collection.get_in_order(self[class], reverse)
end

function Subfactory.get_by_name(self, class, name)
    return Collection.get_by_name(self[class], name)
end

function Subfactory.shift(self, dataset, direction)
    return Collection.shift(self[dataset.class], dataset, direction)
end


-- Removes all lines that are useless (ie have production_ratio of 0)
-- This gets away with only checking the top floor, as no subfloor-lines can become useless if the
-- parent line is still useful, and vice versa (It's still set up to be recursively useable)
function Subfactory.remove_useless_lines(self)
    local function clear_floor(floor)
        for _, line in ipairs(Floor.get_in_order(floor, "Line")) do
            if line.production_ratio == 0 then
                Floor.remove(floor, line)
            end
        end
    end

    local top_floor = Subfactory.get(self, "Floor", 1)
    clear_floor(top_floor)
    self.selected_floor = top_floor
end


-- Returns the machines and modules needed to actually build this subfactory
function Subfactory.get_component_data(self)
    local components = {machines={}, modules={}}

    for _, floor in pairs(Floor.get_in_order(self, "Floor")) do
        -- Relies on the floor-function to do the heavy lifting
        Floor.get_component_data(floor, components)
    end

    return components
end


-- Updates every top level product of this Subfactory to the given product definition type
function Subfactory.update_product_definitions(self, new_defined_by)
    for _, product in pairs(Subfactory.get_in_order(self, "Product")) do
        local req_amount = product.required_amount
        local current_defined_by = req_amount.defined_by
        if current_defined_by ~= "amount" and new_defined_by ~= current_defined_by then
            req_amount.defined_by = new_defined_by

            local multiplier = (new_defined_by == "belts") and 0.5 or 2
            req_amount.amount = req_amount.amount * multiplier
        end
    end
end


-- Updates the validity of the whole subfactory
-- Floors can be checked in any order and separately without problem
function Subfactory.update_validity(self)
    local classes = {Product = "Item", Byproduct = "Item", Ingredient = "Item", Floor = "Floor"}
    self.valid = run_validation_updates(self, classes)
    return self.valid
end

-- Tries to repair all associated datasets, removing the unrepairable ones
-- (In general, Subfactory Items are not repairable and can only be deleted)
function Subfactory.attempt_repair(self, player)
    local classes = {Product = "Item", Byproduct = "Item", Ingredient = "Item"}
    run_invalid_dataset_repair(player, self, classes)

    -- Set selected floor to the top one in case the selected one gets deleted
    Floor.remove_if_empty(self.selected_floor)
    local top_floor = Subfactory.get(self, "Floor", 1)
    self.selected_floor = top_floor
    ui_util.context.set_floor(player, top_floor)

    -- Floor repair is called on the top floor, which recursively goes through its subfloors
    -- (Return value is not caught here because the top level floor won't be removed)
    Floor.attempt_repair(top_floor, player)

    self.valid = true
end