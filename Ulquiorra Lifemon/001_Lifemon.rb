#===============================================================================
# * Plugin: Ulquiorra Lifemon
# * Version: 2.0
# * Credits: UlquiorraSM
#===============================================================================
# * INSTRUCTIONS:
# * This plugin makes wild encounters feel "alive" by adding randomized traits.
# *
# * 1. Historical Encounters: One-time special spawns tied to specific maps.
# * 2. Recovery System: Released Pokémon can be found again in the wild.
# * 3. Form Variations: Species can spawn with randomized forms (cosmetic/stat).
# * 4. Lifemon Mechanics: Random HP, status effects (Sleep/Paralysis), and 
# * custom nicknames with original trainer names.
#===============================================================================

# --- PRESET DATA: HISTORICAL ENCOUNTERS ---
# Add your special "one-time" Pokémon here. 
# Once captured or defeated, they are permanently removed from the array.
LIFEMON_HISTORICAL_DATA = [
  {
    :id           => "ASH_BUTTERFREE_01",
    :species      => :BUTTERFREE,
    :level        => 35,
    :name         => "Butterfree", # Custom Nickname
    :map_id       => 5,            # The Map ID where this Pokémon can spawn
    :chance       => 1,            # 1% chance to replace a standard wild spawn
    :gender       => 1,            # 0 = Male, 1 = Female
    :owner_name   => "Ash",        # Name of the Original Trainer (OT)
    :item         => :SILK_SCARF,
    :moves        => [:GUST, :PSYBEAM, :SLEEP_POWDER, :STUN_SPORE]
  }
]

module LifemonConfig
  # --- General Settings ---
  SHOW_DEBUG_LOGS     = true # If true, shows system activity in the console (F12)
  USE_FORM_VARIATIONS = false  # Toggle the randomized form system on/off
  
  # --- Form Variation Pools ---
  # Define which species get randomized forms. Format: :SPECIES => [Species_1, Species_2]
  POKE_VARIATIONS = {
    :BULBASAUR  => [0, 1, 2]
  }

  # --- Probability Percentages (%) ---
  CHANCE_RECOVERY  = 5  # Chance a released Pokémon returns on its release map
  CHANCE_NICKNAME  = 5  # Chance for any wild Pokémon to have a nickname/OT
  CHANCE_PARALYSIS = 5  # Chance for Paralysis if the spawn has < 50% HP

  # --- Lifemon Mechanics ---
  RANDOM_HP         = true # Enable/Disable random health/damage on wild spawns
  RANDOM_STATUS     = true # Enable/Disable the sleep rhythm system
  
  # Grouping species for the Sleep System
  NOCTURNAL_SPECIES = [:HOOTHOOT, :NOCTOWL, :GHASTLY, :HAUNTER, :GENGAR, :ZUBAT]
  STEADY_SPECIES    = [:MEW, :ARTICUNO, :ZAPDOS, :MOLTRES, :MEWTWO]
  
  # Sleep Rhythms: Chances of finding a Pokémon asleep based on Time of Day
  SLEEP_RHYTHMS     = {
    :normal    => { :day => 12.5, :night => 50.0 }, # Usually sleeps at night
    :nocturnal => { :day => 50.0, :night => 12.5 }, # Usually sleeps during day
    :steady    => { :day => 12.5, :night => 12.5 }  # Rare sleepers (Legends)
  }
  
  # HP Generation: rand(100) check. e.g., if 0-4 is rolled, HP is set to ~25%
  HP_CHANCES  = { 0..4 => 25, 5..14 => 50, 15..29 => 75 }
  HP_VARIANCE = 0.1 # Adds slight variance (e.g., 25% becomes 23% - 27%)

  # --- Cosmetic Pools ---
  NICKNAMES_MALE   = ["Buddy", "Buster", "Zorro", "Mogli", "Rambo", "Rocky", "Duke", "Rex"]
  NICKNAMES_FEMALE = ["Luna", "Cookie", "Honey", "Lulu", "Flora", "Bella", "Peaches", "Mochi"]
  TRAINER_NAMES    = ["Lukas", "Marie", "Tobias", "Sophie", "Felix", "Emma", "Moritz", "Hannah"]
end

# ==============================================================================
# 1. INITIALIZATION & DATA HANDLING
# ==============================================================================
class PokemonGlobalMetadata
  attr_accessor :available_historical_encounters, :released_pokemon_storage
  
  # Create storage for historical data and released Pokémon in new saves
  alias __lifemon_init initialize
  def initialize
    __lifemon_init
    @available_historical_encounters = LIFEMON_HISTORICAL_DATA.clone
    @released_pokemon_storage = []
  end

  # Helpers to prevent crashes if loading an older save file
  def available_historical_encounters; @available_historical_encounters ||= []; end
  def released_pokemon_storage; @released_pokemon_storage ||= []; end
end

# Temporary variables and map memory
class Game_Temp; attr_accessor :historical_pkmn_active; end
class Pokemon; attr_accessor :forget_map_id; end

# Register Form Logic: This runs immediately when a Pokémon is generated
LifemonConfig::POKE_VARIATIONS.each do |species, allowed_forms|
  MultipleForms.register(species, {
    "getFormOnCreation" => proc { |pkmn|
      next LifemonConfig::USE_FORM_VARIATIONS ? allowed_forms.sample : 0
    }
  })
end

# ==============================================================================
# 2. CORE WILD GENERATOR (Event Handler)
# ==============================================================================
EventHandlers.add(:on_wild_pokemon_created, :lifemon_generator,
  proc { |pkmn|
    $game_temp.historical_pkmn_active = nil
    applied_log = []

    # --- BLOCK 1: Historical Encounter Check ---
    # Priority 1: Check if this map has a unique Historical Pokémon waiting
    storage = $PokemonGlobal.available_historical_encounters
    historical_match = storage.find { |data| data[:map_id] == $game_map.map_id }
    
    if historical_match && rand(100) < historical_match[:chance]
      pkmn.species    = historical_match[:species]
      pkmn.level      = historical_match[:level]
      pkmn.name       = historical_match[:name]
      pkmn.gender     = historical_match[:gender] if historical_match[:gender]
      pkmn.item       = historical_match[:item] if historical_match[:item]
      pkmn.owner.name = historical_match[:owner_name] if historical_match[:owner_name]
      if historical_match[:moves]
        pkmn.forget_all_moves
        historical_match[:moves].each { |m| pkmn.learn_move(m) }
      end
      pkmn.calc_stats
      $game_temp.historical_pkmn_active = historical_match
      echoln ">>> [LIFEMON] Historical Spawn: #{pkmn.name}" if LifemonConfig::SHOW_DEBUG_LOGS
      next 
    end

    # --- BLOCK 2: Recovery System ---
    # Priority 2: Check if a released Pokémon is returning to its release map
    rel_storage = $PokemonGlobal.released_pokemon_storage
    if rel_storage && !rel_storage.empty? && rand(100) < LifemonConfig::CHANCE_RECOVERY
      valid_pkmn = rel_storage.select { |p| p.forget_map_id == $game_map.map_id }
      if valid_pkmn.any?
        found = valid_pkmn.sample
        # Restoring all original data (IVs, EVs, Nature, Shiny, etc.)
        [:species, :form, :name, :level, :gender, :ability, :item, :nature].each { |m| pkmn.send("#{m}=", found.send(m)) }
        pkmn.shiny = found.shiny?
        pkmn.iv, pkmn.ev, pkmn.owner = found.iv.clone, found.ev.clone, found.owner.clone
        pkmn.moves = found.moves.map { |m| m.clone }
        pkmn.calc_stats
        $PokemonGlobal.released_pokemon_storage.delete(found)
        echoln ">>> [LIFEMON] Recovery: #{pkmn.name} returned!" if LifemonConfig::SHOW_DEBUG_LOGS
        next 
      end
    end

    # --- BLOCK 3: Lifemon Modifications ---
    
    # 3a. Randomized Nicknames and Owners
    if rand(100) < LifemonConfig::CHANCE_NICKNAME
      if pkmn.male?
        pkmn.name = LifemonConfig::NICKNAMES_MALE.sample
      elsif pkmn.female?
        pkmn.name = LifemonConfig::NICKNAMES_FEMALE.sample
      else
        pkmn.name = (LifemonConfig::NICKNAMES_MALE + LifemonConfig::NICKNAMES_FEMALE).sample
      end
      pkmn.owner.name = LifemonConfig::TRAINER_NAMES.sample
      applied_log.push("Name: #{pkmn.name}")
    end

    # 3b. HP Variance & Injury Mechanic
    if LifemonConfig::RANDOM_HP
      roll = rand(100)
      LifemonConfig::HP_CHANCES.each do |range, percent|
        if range.include?(roll)
          # Calculation: Target % multiplied by random variance (0.9 to 1.1)
          var = 1.0 + (rand - 0.5) * (LifemonConfig::HP_VARIANCE * 2)
          final_pct = (percent * var).clamp(1, 99)
          pkmn.hp = (pkmn.totalhp * (final_pct / 100.0)).floor
          pkmn.hp = 1 if pkmn.hp <= 0
          applied_log.push("HP: #{final_pct.round(1)}%%")
          
          # NEW: Injury Paralysis (Checks if HP is lower than 50%)
          if final_pct < 50 && rand(100) < LifemonConfig::CHANCE_PARALYSIS
            pkmn.status = :PARALYSIS
            applied_log.push("Status: PARALYSIS (Injured)")
          end

          # Reduce PP randomly (simulate a battle-worn state)
          pkmn.moves.each { |m| m.pp = (m.pp * rand(0.4..0.8)).floor if m && m.id != :NONE }
          break
        end
      end
    end

    # 3c. Sleep Rhythms (Only applies if not already Paralyzed)
    if LifemonConfig::RANDOM_STATUS && pkmn.status == :NONE
      rhythm = :normal
      rhythm = :nocturnal if LifemonConfig::NOCTURNAL_SPECIES.include?(pkmn.species)
      rhythm = :steady    if LifemonConfig::STEADY_SPECIES.include?(pkmn.species)
      chance = (PBDayNight.isNight?) ? LifemonConfig::SLEEP_RHYTHMS[rhythm][:night] : LifemonConfig::SLEEP_RHYTHMS[rhythm][:day]
      if rand(100) < chance
        pkmn.status = :SLEEP; pkmn.statusCount = rand(1..5)
        applied_log.push("Status: SLEEP")
      end
    end

    # Log results to console if Debug Logs are enabled
    if !applied_log.empty? && LifemonConfig::SHOW_DEBUG_LOGS
      echoln ">>> [LIFEMON] #{pkmn.species}: " + applied_log.join(" | ")
    end
  }
)

# ==============================================================================
# 3. SCENE & SYSTEM INTEGRATION
# ==============================================================================

# Evolution Logic: Handles form rolling during the evolution sequence
class PokemonEvolutionScene
  alias __lifemon_pbStartScreen pbStartScreen
  alias __lifemon_pbEvolution pbEvolution

  def pbStartScreen(pokemon, newspecies)
    @old_form_backup = pokemon.form # Remember original form in case of cancellation
    __lifemon_pbStartScreen(pokemon, newspecies)
    
    if LifemonConfig::USE_FORM_VARIATIONS && LifemonConfig::POKE_VARIATIONS.key?(newspecies)
      new_f = LifemonConfig::POKE_VARIATIONS[newspecies].sample
      pokemon.form = new_f
      @sprites["rsprite2"].setPokemonBitmapSpecies(pokemon, newspecies, false) if @sprites["rsprite2"]
      echoln ">>> [LIFEMON] Evolution Form Rolled: #{new_f}" if LifemonConfig::SHOW_DEBUG_LOGS
    end
  end

  # Revert form if the player cancels the evolution
  def pbEvolution(cancancel = true)
    canceled = __lifemon_pbEvolution(cancancel)
    if @pokemon.species != @newspecies
      @pokemon.form = @old_form_backup
      @pokemon.calc_stats
    end
    return canceled
  end
end

# Release Handler: Stores map data when a Pokémon is set free
EventHandlers.add(:on_pokemon_released, :lifemon_release_handler,
  proc { |pkmn|
    pkmn.forget_map_id = $game_map.map_id 
    $PokemonGlobal.released_pokemon_storage.push(pkmn)
    echoln ">>> [LIFEMON] Saved released #{pkmn.name} for Map #{$game_map.map_id}." if LifemonConfig::SHOW_DEBUG_LOGS
  }
)

# Cleanup: Removes historical data from the world if caught or defeated
EventHandlers.add(:on_wild_battle_end, :lifemon_historical_cleanup,
  proc { |species, level, decision|
    if $game_temp.historical_pkmn_active && [1, 4].include?(decision) # 1=Won, 4=Caught
      active_id = $game_temp.historical_pkmn_active[:id]
      $PokemonGlobal.available_historical_encounters.delete_if { |p| p[:id] == active_id }
      echoln ">>> [LIFEMON] Historical #{active_id} removed from world." if LifemonConfig::SHOW_DEBUG_LOGS
    end
    $game_temp.historical_pkmn_active = nil
  }
)
