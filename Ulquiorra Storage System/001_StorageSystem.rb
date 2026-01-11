#===============================================================================
#
# Chest System
# By UlquiorraSM
#
# How does that work?:
# There are two types of chests: "only_take" and "normal_chest".
#
# With "normal_chest", you can add and remove items.
#
# With "only_take", you can only remove items; it's ideal for trash cans.
#
# You use them in the event below the script: "ChestSystem.normal_chest(1)" or "ChestSystem.only_take(1, self)", 
# the first number is the ID, both variants do not share the same ID.
#
# You can adjust the maximum number of items that can go in. If you only want 15 items, 
# you write the script like this: "ChestSystem.normal_chest(1, 15)". This is irrelevant for only_take.
#
# You can add items to both variants, for example: "ChestSystem.normal_chest(2, 15, "Chest", [[:POTION, 2]])" 
# or "ChestSystem.normal_chest(2, 15, "Chest", [[:POTION, 5], [:POKEBALL, 10]])" and for only_take like 
# this: "ChestSystem.only_take(1, self, "Nightstand", [[:POKEBALL, 2]])"
#
# With "only_take" you need to add "self", like this: "ChestSystem.only_take(1, self, "Nightstand")". Without it, "only_take" won't work.
#
# IMPORTANT: You need a name for each one. The name is used like this: "ChestSystem.normal_chest(2, 15, "Chest")" and 
# for only_take like this: "ChestSystem.only_take(1, self, "Nightstand")". Without a name, the script will not respond.
#
# Examples:
#   1. A simple storage box (ID 1, 20 Slots):
#      ChestSystem.normal_chest(1, 20, "Storage Box")
#
#   2. A bookshelf that already contains some items (ID 2, 10 Slots):
#      ChestSystem.normal_chest(2, 10, "Bookshelf", [[:OLDGATEAU, 1], [:PEWTERCRUNCHER, 2]])
#
#   3. A trash can where you can only take what's inside (ID 1, Only-Take):
#      ChestSystem.only_take(1, self, "Trash Can", [[:ORANBERRY, 1]])
#
#   4. A hidden stash in a nightstand (ID 5, Only-Take, multiple items):
#      ChestSystem.only_take(5, self, "Nightstand", [[:POTION, 3], [:ETHER, 1], [:POKEBALL, 5]])
#
#   5. A large fridge (ID 10, 50 Slots, no initial items):
#      ChestSystem.normal_chest(10, 50, "Fridge")
#
#===============================================================================

class PokemonGlobalMetadata
  attr_accessor :chests
  alias initialize_chest_system initialize
  def initialize
    initialize_chest_system
    @chests = {}
  end
end

class ChestStorage
  MAX_POCKETS = 8
  attr_accessor :max_slots, :max_stack, :total_max_items, :name

  def initialize(name = "Chest", total_max_items = 99999, max_slots = 99999, max_stack = 999)
    @storage = Array.new(MAX_POCKETS) { [] }
    @name = name
    @total_max_items = total_max_items
    @max_slots       = max_slots
    @max_stack       = max_stack
  end

  def storage_data
    @storage = Array.new(MAX_POCKETS) { [] } if !@storage
    return @storage
  end

  def all_items_flat
    flat_list = []
    storage_data.each { |pocket| 
      next if !pocket
      pocket.each { |item_stack| flat_list.push(item_stack) if item_stack } 
    }
    return flat_list
  end

  def quantity(item)
    ret = 0
    storage_data.each { |p| p.each { |s| ret += s[1] if s && s[0] == item } }
    return ret
  end

  def total_quantity
    ret = 0
    storage_data.each { |p| p.each { |slot| ret += slot[1] if slot } }
    return ret
  end

  def can_add?(item, qty = 1)
    return false if !item || qty < 1
    return false if total_quantity + qty > (@total_max_items || 99999)
    item_data = GameData::Item.get(item)
    target_pocket = storage_data[item_data.pocket - 1]
    max_s = @max_stack || 999
    return true if !item_data.is_important? && target_pocket.any? { |s| s[0] == item && s[1] + qty <= max_s }
    return target_pocket.length < (@max_slots || 99999)
  end

  def add(item, qty = 1)
    return false if !can_add?(item, qty)
    item_data = GameData::Item.get(item)
    target_pocket = storage_data[item_data.pocket - 1]
    max_s = @max_stack || 999
    if !item_data.is_important?
      target_pocket.each do |slot|
        if slot[0] == item
          added = [max_s - slot[1], qty].min
          slot[1] += added
          qty -= added
        end
      end
    end
    while qty > 0 && target_pocket.length < (@max_slots || 99999)
      added = item_data.is_important? ? 1 : [max_s, qty].min
      target_pocket.push([item, added])
      qty -= added
    end
    return qty == 0
  end

  def remove(item, qty = 1)
    storage_data.each do |pocket|
      pocket.each_with_index do |slot, i|
        next if !slot || slot[0] != item
        take = [slot[1], qty].min
        slot[1] -= take
        qty -= take
        pocket.delete_at(i) if slot[1] <= 0
        return true if qty == 0
      end
    end
    return qty == 0
  end
end

module ChestSystem
  def self.normal_chest(chest_id, total_limit = 99999, name = "Chest", items_array = [])
    $PokemonGlobal.chests ||= {}
    full_id = "N_#{chest_id}"
    
    if !$PokemonGlobal.chests[full_id]
      storage = $PokemonGlobal.chests[full_id] = ChestStorage.new(name, total_limit)
      items_array.each do |item_data|
        item_id = item_data[0]
        quantity = item_data[1] || 1
        storage.add(item_id, quantity) if GameData::Item.exists?(item_id)
      end
    else
      storage = $PokemonGlobal.chests[full_id]
      storage.name = name
      storage.total_max_items = total_limit
    end
    
    commands = [_INTL("Withdraw Item"), _INTL("Deposit Item"), _INTL("Cancel")]
    cmd = 0
    loop do
      cmd = pbMessage(_INTL("What would you like to do with the {1}?", storage.name), commands, cmd)
      case cmd
      when 0 then self.open_withdraw_scene(storage)
      when 1 then self.open_deposit_scene(storage)
      else break
      end
    end
  end

  def self.only_take(chest_id, interpreter, name = "Chest", items_array = [])
    $PokemonGlobal.chests ||= {}
    full_id = "L_#{chest_id}"
    
    if !$PokemonGlobal.chests[full_id]
      storage = $PokemonGlobal.chests[full_id] = ChestStorage.new(name)
      items_array.each do |item_data|
        item_id = item_data[0]
        quantity = item_data[1] || 1
        storage.add(item_id, quantity) if GameData::Item.exists?(item_id)
      end
      $PokemonGlobal.chests["#{full_id}_init"] = true
    else
      storage = $PokemonGlobal.chests[full_id]
      storage.name = name
    end

    self.open_withdraw_scene(storage)
  end

  def self.open_withdraw_scene(storage)
    pbFadeOutIn(99999) {
      scene = WithdrawItemScene.new
      screen = PokemonChestWithdrawScreen.new(scene, storage)
      screen.pbStartScreen
    }
  end

  def self.open_deposit_scene(storage)
    pbFadeOutIn(99999) {
      scene = PokemonBag_Scene.new
      screen = PokemonBagScreen.new(scene, storage)
      screen.pbDepositItemScreenToChest(storage)
    }
  end
end

class PokemonChestWithdrawScreen
  def initialize(scene, storage); @storage = storage; @scene = scene; end
  def pbStartScreen
    loop do
      item_list = @storage.all_items_flat || []
      @scene.pbStartScene(item_list)
      item = @scene.pbChooseItem
      if item
        itm_data = GameData::Item.get(item)
        can_take = [@storage.quantity(item), Settings::BAG_MAX_PER_SLOT - $bag.quantity(item)].min
        if can_take <= 0
          @scene.pbDisplay(_INTL("Your Bag is full!"))
        else
          qty = 1
          qty = @scene.pbChooseNumber(_INTL("How many to withdraw?"), can_take) if can_take > 1 && !itm_data.is_important?
          if qty > 0
            $bag.add(item, qty)
            @storage.remove(item, qty)
            @scene.pbDisplay(_INTL("Withdrew {1}.", itm_data.name))
          end
        end
        @scene.pbRefresh
        @scene.pbEndScene
      else
        @scene.pbEndScene
        break
      end
    end
  end
end

class PokemonBagScreen
  def pbDepositItemScreenToChest(storage)
    @scene.pbStartScene($bag, nil, nil, false)
    loop do
      item = @scene.pbChooseItem
      break if !item
      itm = GameData::Item.get(item)
      qty_can_add = [$bag.quantity(item), (storage.max_stack || 999) - storage.quantity(item), (storage.total_max_items || 99999) - storage.total_quantity].min
      if qty_can_add <= 0
        pbMessage(_INTL("The {1} is full!", storage.name))
        next
      end
      qty = 1
      qty = @scene.pbChooseNumber(_INTL("How many to deposit?"), qty_can_add) if qty_can_add > 1 && !itm.is_important?
      if qty > 0 && storage.can_add?(item, qty)
        $bag.remove(item, qty)
        storage.add(item, qty)
        @scene.pbRefresh
        pbMessage(_INTL("Deposited {1}.", itm.name))
      end
    end
    @scene.pbEndScene
  end
end
