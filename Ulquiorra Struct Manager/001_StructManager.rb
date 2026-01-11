#===============================================================================
# * Plugin: Ulquiorra Struct Manager
# * Version: 1.0
# * Credits: UlquiorraSM
#===============================================================================
# HOW TO USE:
#
# --- HELPER COMMANDS ---
# pbCheckVarNPC(:ID, :VAR, :symbol, value) -> e.g., pbCheckVarNPC(:YUKES, :affection, :>, 10)
# pbToggleNPC(:ID, :SWITCH)               -> Switches true to false or false to true
# pbResetNPC(:ID)                         -> Resets NPC to DB default values
# pbHasNPC(:ID)                           -> Returns true if NPC exists in DB
#
# --- CLASSIC COMMANDS ---
# pbCheckNPC(:ID, :SWITCH)                -> Returns true/false
# pbSetNPC(:ID, :VAR, value)              -> Sets variable
# pbChangeNPC(:ID, :VAR, amount)          -> Adds/Subtracts from variable
# pbSwitchNPC(:ID, :SWITCH, true/false)   -> Sets switch
#
#===============================================================================
# EXAMPLES & USE CASES:
#
# 1. Dialogue Branching based on Affection (Conditional Branch -> Script):
#    pbCheckVarNPC(:YUKES, :affection, :>=, 50)
#    -> If true, Yukes acts like a close friend.
#
# 2. Simple Quest Progression (Script Command):
#    pbSetNPC(:YUKES, :state, 1) 
#    -> Sets Yukes quest state to 1.
#
# 3. Killing/Reviving an NPC (Script Command):
#    pbSwitchNPC(:YUKES, :alive, false)
#    -> Yukes is now "dead" in your global data.
#
# 4. Toggling a Secret Door or Event (Script Command):
#    pbToggleNPC(:VIRIDIANCITY, :OwnHouse)
#    -> If the player owned the house, they now don't (and vice versa).
#
# 5. Reward System (Script Command):
#    pbChangeNPC(:YUKES, :affection, 5)
#    -> Increases Yukes' affection by 5 points.
#
# 6. Safety Check before running logic (Conditional Branch -> Script):
#    pbHasNPC(:YUKES)
#    -> Checks if "Yukes" is actually defined in your Database to prevent errors.
#
# 7. Complete Data Wipe (Script Command):
#    pbResetNPC(:YUKES)
#    -> Useful for "New Game Plus" or if an NPC's memory is wiped in-story.
#===============================================================================

module NPC_DB
  DB = {
    #--- Yukes ---
    :YUKES => {
      :variables => { :affection => 10, :state => 0 },
      :switches  => { :alive => true, :unknow => true, :known => false, :friend => false, :enemy => false }
    },
    #--- Viridian City ---
    :VIRIDIANCITY => {
      :variables => { :state => 0 },
      :switches  => { :OwnHouse => false }
    }
  }
end

#===============================================================================
# NPC State Class
#===============================================================================
class Game_NPC_State
  attr_accessor :variables, :switches, :id

  def initialize(key)
    @id = key.to_s.upcase.to_sym
    reset_to_default
  end

  def reset_to_default
    data = NPC_DB::DB[@id]
    return if data.nil?
    @variables = data[:variables] ? data[:variables].clone : {}
    @switches  = data[:switches]  ? data[:switches].clone  : {}
  end

  def v(name); return @variables[name] || 0; end
  def s(name); return @switches[name] || false; end

  def set_v(name, val); @variables[name] = val; end
  def set_s(name, val); @switches[name] = val; end

  def change_v(name, amount)
    @variables[name] = 0 if !@variables[name].is_a?(Numeric)
    @variables[name] += amount
  end

  def toggle_s(name)
    @switches[name] = !@switches[name]
  end
end

#===============================================================================
# NPC Tracker
#===============================================================================
class NPC_Tracker
  attr_accessor :npcs

  def initialize; @npcs = {}; end

  def get_npc(key)
    key = key.to_s.upcase.to_sym
    if !NPC_DB::DB.key?(key)
      echopn "WARNING: NPC '#{key}' not found in NPC_DB!"
      return nil 
    end
    @npcs[key] = Game_NPC_State.new(key) if !@npcs.key?(key)
    return @npcs[key]
  end
end

#===============================================================================
# SaveData Integration
#===============================================================================
SaveData.register(:npc_tracker) do
  ensure_class :NPC_Tracker
  save_value       { $npc_data }
  load_value       { |v| $npc_data = v }
  new_game_value   { NPC_Tracker.new }
end

#===============================================================================
# Global Helper Functions
#===============================================================================

def pbGetNPC(key)
  $npc_data = NPC_Tracker.new if !$npc_data
  return $npc_data.get_npc(key)
end

def pbCheckNPC(npc_key, switch_key)
  npc = pbGetNPC(npc_key)
  return npc ? npc.s(switch_key) : false
end

def pbSwitchNPC(npc_key, switch_key, value)
  npc = pbGetNPC(npc_key)
  npc.set_s(switch_key, value) if npc
end

def pbSetNPC(npc_key, var_key, value)
  npc = pbGetNPC(npc_key)
  npc.set_v(var_key, value) if npc
end

def pbChangeNPC(npc_key, var_key, amount)
  npc = pbGetNPC(npc_key)
  npc.change_v(var_key, amount) if npc
end

def pbToggleNPC(npc_key, switch_key)
  npc = pbGetNPC(npc_key)
  npc.toggle_s(switch_key) if npc
end

def pbResetNPC(npc_key)
  npc = pbGetNPC(npc_key)
  npc.reset_to_default if npc
end

def pbCheckVarNPC(npc_key, var_key, comparison, value)
  npc = pbGetNPC(npc_key)
  return false if !npc
  current_val = npc.v(var_key)
  case comparison
  when :== then return current_val == value
  when :!= then return current_val != value
  when :>  then return current_val > value
  when :<  then return current_val < value
  when :>= then return current_val >= value
  when :<= then return current_val <= value
  end
  return false
end

def pbHasNPC(npc_key)
  return NPC_DB::DB.key?(npc_key.to_s.upcase.to_sym)
end
