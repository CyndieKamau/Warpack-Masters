#[dojo::interface]
trait IFight {
    fn match_dummy(ref world: IWorldDispatcher);
    fn fight(ref world: IWorldDispatcher);
}

#[dojo::contract]
mod fight_system {
    use super::IFight;

    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use warpack_masters::models::{
        CharacterItem::{Position, CharacterItemInventory, CharacterItemsInventoryCounter},
        Item::Item
    };
    use warpack_masters::models::Character::{Characters, WMClass, PLAYER, DUMMY};

    use warpack_masters::utils::random::{pseudo_seed, random};
    use warpack_masters::utils::sort_items::{append_item, order_items};
    use warpack_masters::models::DummyCharacter::{DummyCharacter, DummyCharacterCounter};
    use warpack_masters::models::DummyCharacterItem::{
        DummyCharacterItem, DummyCharacterItemsCounter
    };
    use warpack_masters::models::Fight::{BattleLog, BattleLogCounter, CharStatus, BattleLogDetail};
    use warpack_masters::constants::constants::{EFFECT_DAMAGE, EFFECT_CLEANSE_POISON, EFFECT_REGEN, EFFECT_REFLECT, EFFECT_POISON, EFFECT_VAMPIRISM};

    #[abi(embed_v0)]
    impl FightImpl of IFight<ContractState> {
        fn match_dummy(ref world: IWorldDispatcher) {
            let player = get_caller_address();

            let mut char = get!(world, player, (Characters));

            assert(char.dummied == true, 'dummy not created');
            assert(char.loss < 5, 'max loss reached');

            let (seed1, _, _, _) = pseudo_seed();
            let dummyCharCounter = get!(world, char.wins, (DummyCharacterCounter));
            assert(dummyCharCounter.count > 1, 'only self dummy created');

            let mut battleLogCounter = get!(world, player, (BattleLogCounter));
            let latestBattleLog = get!(world, (player, battleLogCounter.count), BattleLog);
            assert(battleLogCounter.count == 0 || latestBattleLog.winner != 0, 'battle not fought');

            let random_index = random(seed1, dummyCharCounter.count) + 1;
            let mut dummy_index = random_index;
            let mut dummyChar = get!(world, (char.wins, dummy_index), DummyCharacter);

            while dummyChar.player == player {
                dummy_index = dummy_index % dummyCharCounter.count + 1;
                assert(dummy_index != random_index, 'no others dummy found');
                dummyChar = get!(world, (char.wins, dummy_index), DummyCharacter);
            };

            let mut items_cooldown4 = ArrayTrait::new();
            let mut items_cooldown5 = ArrayTrait::new();
            let mut items_cooldown6 = ArrayTrait::new();
            let mut items_cooldown7 = ArrayTrait::new();

            // =========  buffs/debuffs stacks ========= 
            let mut char_armor: usize = 0;
            let mut dummy_armor: usize = 0;

            let mut char_regen: usize = 0;
            let mut dummy_regen: usize = 0;

            let mut char_reflect: usize = 0;
            let mut dummy_reflect: usize = 0;

            let mut char_empower: usize = 0;
            let mut dummy_empower: usize = 0;

            let mut char_vampirism: usize = 0;
            let mut dummy_vampirism: usize = 0;

            let mut char_poison: usize = 0;
            let mut dummy_poison: usize = 0;
            // =========  end =========

            let mut char_on_hit_items = ArrayTrait::new();
            let mut dummy_on_hit_items = ArrayTrait::new();

            let mut char_on_attack_items = ArrayTrait::new();
            let mut dummy_on_attack_items = ArrayTrait::new();

            let inventoryItemsCounter = get!(world, player, (CharacterItemsInventoryCounter));
            let mut inventoryItemCount = inventoryItemsCounter.count;

            let mut items_length: usize = 0;
            loop {
                if inventoryItemCount == 0 {
                    break;
                }
                let charItem = get!(world, (player, inventoryItemCount), (CharacterItemInventory));

                let item = get!(world, charItem.itemId, (Item));
                if item.itemType == 4 {
                    inventoryItemCount -= 1;
                    continue;
                }
                
                // if item.cooldown > 0 its effectActivationType must be 3 - On Cooldown
                if item.cooldown > 0 && item.effectActivationType == 3 {
                    match item.cooldown {
                        0 | 1 | 2 | 3 => {
                            assert(false, 'cooldown not valid');
                        },
                        4 => {
                            append_item(ref items_cooldown4, charItem.plugins.span(), @item, PLAYER);
                        },
                        5 => {
                            append_item(ref items_cooldown5, charItem.plugins.span(), @item, PLAYER);
                        },
                        6 => {
                            append_item(ref items_cooldown6, charItem.plugins.span(), @item, PLAYER);
                        },
                        7 => {
                            append_item(ref items_cooldown7, charItem.plugins.span(), @item, PLAYER);
                        },
                        _ => {
                            assert(false, 'cooldown not valid');
                        },
                    }

                    items_length += 1;
                } else {
                    // ====== `on start -- 1 / on hit -- 2 / on attack -- 4` to plus stacks ======
                    if item.effectActivationType == 1 {
                        if item.effectType == 3 {
                            char_armor += item.effectStacks;
                        } else if item.effectType == 4 {
                            char_regen += item.effectStacks;
                        } else if item.effectType == 5 {
                            char_reflect += item.effectStacks;
                        } else if item.effectType == 7 {
                            char_empower += item.effectStacks;
                        } else if item.effectType == 8 {
                            char_vampirism += item.effectStacks;
                        } else if item.effectType == 6 {
                            dummy_poison += item.effectStacks;
                        }
                    }

                    if item.effectActivationType == 2 {
                        char_on_hit_items.append((item.effectType, item.chance, item.effectStacks));
                    }

                    if item.effectActivationType == 4 {
                        char_on_attack_items.append((item.effectType, item.chance, item.effectStacks));
                    }
                    // ====== plus stacks end ======
                }

                inventoryItemCount -= 1;
            };

            let dummyCharItemsCounter = get!(
                world, (char.wins, dummy_index), DummyCharacterItemsCounter
            );
            let mut dummy_item_count = dummyCharItemsCounter.count;
            loop {
                if dummy_item_count == 0 {
                    break;
                }

                let dummy_item = get!(
                    world, (char.wins, dummy_index, dummy_item_count), DummyCharacterItem
                );

                let item = get!(world, dummy_item.itemId, (Item));
                if item.itemType == 4 {
                    dummy_item_count -= 1;
                    continue;
                }

                if item.cooldown > 0 {
                    match item.cooldown {
                        0 | 1 | 2 | 3 => {
                            assert(false, 'cooldown not valid');
                        },
                        4 => {
                            append_item(ref items_cooldown4, dummy_item.plugins, @item, DUMMY);
                        },
                        5 => {
                            append_item(ref items_cooldown5, dummy_item.plugins, @item, DUMMY);
                        },
                        6 => {
                            append_item(ref items_cooldown6, dummy_item.plugins, @item, DUMMY);
                        },
                        7 => {
                            append_item(ref items_cooldown7, dummy_item.plugins, @item, DUMMY);
                        },
                        _ => {
                            assert(false, 'cooldown not valid');
                        },
                    }

                    items_length += 1;
                } else {
                    // ====== `on start / on hit / on attack` to plus stacks ======
                    if item.effectActivationType == 1 {
                        if item.effectType == 3 {
                            dummy_armor += item.effectStacks;
                        } else if item.effectType == 4 {
                            dummy_regen += item.effectStacks;
                        } else if item.effectType == 5 {
                            dummy_reflect += item.effectStacks;
                        } else if item.effectType == 7 {
                            dummy_empower += item.effectStacks;
                        } else if item.effectType == 8 {
                            dummy_vampirism += item.effectStacks;
                        } else if item.effectType == 6 {
                            char_poison += item.effectStacks;
                        }
                    }

                    if item.effectActivationType == 2 {
                        dummy_on_hit_items.append((item.effectType, item.chance, item.effectStacks));
                    }

                    if item.effectActivationType == 4 {
                        dummy_on_attack_items.append((item.effectType, item.chance, item.effectStacks));
                    }
                    // ====== plus stacks end ======
                }

                dummy_item_count -= 1;
            };

            // combine items
            let sorted_items = order_items(
                ref items_cooldown4,
                ref items_cooldown5,
                ref items_cooldown6,
                ref items_cooldown7,
            );

            // record the battle log
            battleLogCounter.count += 1;

            let battleLog = BattleLog {
                player: player,
                id: battleLogCounter.count,
                dummyLevel: char.wins,
                dummyCharId: dummy_index,
                sorted_items: sorted_items.span(),
                items_length: items_length,
                char_buffs: array![char_armor, char_regen, char_reflect, char_empower, char_poison, char_vampirism].span(),
                dummy_buffs: array![dummy_armor, dummy_regen, dummy_reflect, dummy_empower, dummy_poison, dummy_vampirism].span(),
                char_on_hit_items: char_on_hit_items.span(),
                dummy_on_hit_items: dummy_on_hit_items.span(),
                char_on_attack_items: char_on_attack_items.span(),
                dummy_on_attack_items: dummy_on_attack_items.span(),
                winner: 0,
                seconds: 0,
            };
            set!(world, (battleLogCounter, battleLog));
        }

        fn fight(ref world: IWorldDispatcher) {
            let player = get_caller_address();

            let mut char = get!(world, player, (Characters));

            let battleLogCounter = get!(world, player, (BattleLogCounter));
            let mut battleLog = get!(world, (player, battleLogCounter.count), BattleLog);

            let battleLogCounterCount = battleLogCounter.count;

            assert(battleLogCounterCount != 0 && battleLog.winner == 0, 'no new match found');

            let dummy_index = battleLog.dummyCharId;
            let mut dummyChar = get!(world, (char.wins, dummy_index), DummyCharacter);

            let char_health_flag: usize = char.health;
            let char_buffs = battleLog.char_buffs;
            let mut playerStatus = CharStatus {
                hp: char.health,
                stamina: char.stamina,
                armor: *battleLog.char_buffs.at(0),
                regen: *battleLog.char_buffs.at(1),
                reflect: *battleLog.char_buffs.at(2),
                empower: *battleLog.char_buffs.at(3),
                poison: *battleLog.char_buffs.at(4),
                vampirism: *battleLog.char_buffs.at(5),
            };

            let dummy_health_flag: usize = dummyChar.health;
            let dummy_buffs = battleLog.dummy_buffs;
            let mut dummyStatus = CharStatus {
                hp: dummyChar.health,
                stamina: dummyChar.stamina,
                armor: *battleLog.dummy_buffs.at(0),
                regen: *battleLog.dummy_buffs.at(1),
                reflect: *battleLog.dummy_buffs.at(2),
                empower: *battleLog.dummy_buffs.at(3),
                poison: *battleLog.dummy_buffs.at(4),
                vampirism: *battleLog.dummy_buffs.at(5),
            };

            let sorted_items = battleLog.sorted_items;
            let items_length = battleLog.items_length;

            let char_on_hit_items_span = battleLog.char_on_hit_items;
            let char_on_attack_items_span = battleLog.char_on_attack_items;

            let dummy_on_hit_items_span = battleLog.dummy_on_hit_items;
            let dummy_on_attack_items_span = battleLog.dummy_on_attack_items;

            // record the battle log
            let mut battleLogsCount = 0;

            // battle logic
            let mut seconds = 0;
            let mut winner = '';

            let mut rand = 0;
            let mut v = 0;

            emit!(
                world,
                (BattleLogDetail {
                    player,
                    battleLogId: battleLogCounterCount,
                    id: battleLogsCount,
                    whoTriggered: 0,
                    whichItem: 0,
                    isDodged: false,
                    effectType: 0,
                    effectStacks: 0,
                    player_remaining_health: playerStatus.hp,
                    dummy_remaining_health: dummyStatus.hp,
                    player_stamina: playerStatus.stamina,
                    dummy_stamina: dummyStatus.stamina,
                    player_stacks: (playerStatus.armor, playerStatus.regen, playerStatus.reflect, playerStatus.empower, playerStatus.poison, playerStatus.vampirism),
                    dummy_stacks: (dummyStatus.armor, dummyStatus.regen, dummyStatus.reflect, dummyStatus.empower, dummyStatus.poison, dummyStatus.vampirism),
                })
            );

            loop {
                seconds += 1;
                if seconds >= 25_u8 {
                    if char_health <= dummy_health {
                        winner = DUMMY;
                    } else {
                        winner = PLAYER;
                    }
                    break;
                }

                let mut i: usize = 0;

                // Skip stamina regeneration on the first second
                if seconds > 1 {
                    // Regenerate stamina for both player and dummy at the beginning of each cycle
                    if char_stamina < 100 {
                        char_stamina += 10;
                        if char_stamina > 100 {
                            char_stamina = 100;
                        }
                    }

                    if dummy_stamina < 100 {
                        dummy_stamina += 10;
                        if dummy_stamina > 100 {
                            dummy_stamina = 100;
                        }
                    }
                }

                loop {
                    if i == items_length {
                        break;
                    }

                    let (curr_item_belongs, curr_item_index, item_type, effect_type, chance, effect_stacks, cooldown, energy_cost, plugins) = *sorted_items.at(i);
                    let opponent = if curr_item_belongs == PLAYER {
                        DUMMY
                    } else {
                        PLAYER
                    };
                    // each second is treated as 1 unit of cooldown 
                    let (_, seed2, _, _) = pseudo_seed();
                    if seconds % cooldown == 0 {
                        v += seconds.into();
                        rand = random(seed2 + v, 100);
                        if rand < chance {
                            if curr_item_belongs == PLAYER {
                                if energy_cost > playerStatus.stamina {
                                    i += 1;
                                    continue;
                                }
                                // Deduct stamina
                                playerStatus.stamina -= energy_cost;

                                attack(
                                    world,
                                    playerStatus,
                                    dummyStatus,
                                    curr_item_belongs,
                                    curr_item_index,
                                    item_type,
                                    effect_type,
                                    effect_stacks,
                                    plugins,
                                );
                            } else if curr_item_belongs == DUMMY {
                                if energy_cost > dummyStatus.stamina {
                                    i += 1;
                                    continue;
                                }
                                // Deduct stamina
                                dummyStatus.stamina -= energy_cost;

                                attack(
                                    world,
                                    dummyStatus,
                                    playerStatus,
                                    curr_item_belongs,
                                    curr_item_index,
                                    item_type,
                                    effect_type,
                                    effect_stacks,
                                    plugins,
                                );
                            } else {
                                assert(false, 'curr_item_belongs not valid');
                            }
                        } else if rand >= chance && effect_type == 1 {
                            battleLogsCount += 1;
                            emit!(
                                world,
                                (BattleLogDetail {
                                    player,
                                    battleLogId: battleLogCounterCount,
                                    id: battleLogsCount,
                                    whoTriggered: curr_item_belongs,
                                    whichItem: curr_item_index,
                                    isDodged: true,
                                    effectType: effect_type,
                                    effectStacks: 0,
                                    player_remaining_health: char_health,
                                    dummy_remaining_health: dummy_health,
                                    player_stamina: char_stamina,
                                    dummy_stamina: dummy_stamina,
                                    player_stacks: (char_armor, char_regen, char_reflect, char_empower, char_poison, char_vampirism),
                                    dummy_stacks: (dummy_armor, dummy_regen, dummy_reflect, dummy_empower, dummy_poison, dummy_vampirism),
                                })
                            );
                        }
                    }

                    i += 1;
                };

                if winner != '' {
                    break;
                }

                // ====== Poison effect: Deals 1 damage per stack every 2 seconds. ======
                // ====== Heal effect: Regenerate 1 health per stack every 2 seconds. ======
                if seconds % 2 == 0 {
                    if playerStatus.poison > 0 {
                        playerStatus.hp = if playerStatus.hp <= playerStatus.poison {
                            0
                        } else {
                            playerStatus.hp - playerStatus.poison
                        };

                        battleLogsCount += 1;
                        emit!(
                            world,
                            (BattleLogDetail {
                                player,
                                battleLogId: battleLogCounterCount,
                                id: battleLogsCount,
                                whoTriggered: DUMMY,
                                whichItem: 0,
                                isDodged: false,
                                effectType: EFFECT_POISON,
                                effectStacks: playerStatus.poison,
                                player_remaining_health: playerStatus.hp,
                                dummy_remaining_health: dummyStatus.hp,
                                player_stamina: playerStatus.stamina,
                                dummy_stamina: dummyStatus.stamina,
                                player_stacks: (playerStatus.armor, playerStatus.regen, playerStatus.reflect, playerStatus.empower, playerStatus.poison, playerStatus.vampirism),
                                dummy_stacks: (dummyStatus.armor, dummyStatus.regen, dummyStatus.reflect, dummyStatus.empower, dummyStatus.poison, dummyStatus.vampirism),
                            })
                        );

                        if playerStatus.hp == 0 {
                            winner = DUMMY;
                            break;
                        }
                    }
                    if dummyStatus.poison > 0 {
                        dummyStatus.hp = if dummyStatus.hp <= dummyStatus.poison {
                            0
                        } else {
                            dummyStatus.hp - dummyStatus.poison
                        };

                        battleLogsCount += 1;
                        emit!(
                            world,
                            (BattleLogDetail {
                                player,
                                battleLogId: battleLogCounterCount,
                                id: battleLogsCount,
                                whoTriggered: PLAYER,
                                whichItem: 0,
                                isDodged: false,
                                effectType: EFFECT_POISON,
                                effectStacks: dummyStatus.poison,
                                player_remaining_health: playerStatus.hp,
                                dummy_remaining_health: dummyStatus.hp,
                                player_stamina: playerStatus.stamina,
                                dummy_stamina: dummyStatus.stamina,
                                player_stacks: (playerStatus.armor, playerStatus.regen, playerStatus.reflect, playerStatus.empower, playerStatus.poison, playerStatus.vampirism),
                                dummy_stacks: (dummyStatus.armor, dummyStatus.regen, dummyStatus.reflect, dummyStatus.empower, dummyStatus.poison, dummyStatus.vampirism),
                            })
                        );

                        if dummyStatus.hp == 0 {
                            winner = PLAYER;
                            break;
                        }
                    }
                    if playerStatus.regen > 0 {
                        playerStatus.hp = if playerStatus.hp + playerStatus.regen > char_health_flag {
                            char_health_flag
                        } else {
                            playerStatus.hp + playerStatus.regen
                        };

                        battleLogsCount += 1;
                        emit!(
                            world,
                            (BattleLogDetail {
                                player,
                                battleLogId: battleLogCounterCount,
                                id: battleLogsCount,
                                whoTriggered: PLAYER,
                                whichItem: 0,
                                isDodged: false,
                                effectType: EFFECT_REGEN,
                                effectStacks: playerStatus.regen,
                                player_remaining_health: playerStatus.hp,
                                dummy_remaining_health: dummyStatus.hp,
                                player_stamina: playerStatus.stamina,
                                dummy_stamina: dummyStatus.stamina,
                                player_stacks: (playerStatus.armor, playerStatus.regen, playerStatus.reflect, playerStatus.empower, playerStatus.poison, playerStatus.vampirism),
                                dummy_stacks: (dummyStatus.armor, dummyStatus.regen, dummyStatus.reflect, dummyStatus.empower, dummyStatus.poison, dummyStatus.vampirism),
                            })
                        );
                    }
                    if dummyStatus.poison > 0 {
                        dummyStatus.hp = if dummyStatus.hp + dummyStatus.regen > dummy_health_flag {
                            dummy_health_flag
                        } else {
                            dummyStatus.hp + dummyStatus.regen
                        };

                        battleLogsCount += 1;
                        emit!(
                            world,
                            (BattleLogDetail {
                                player,
                                battleLogId: battleLogCounterCount,
                                id: battleLogsCount,
                                whoTriggered: DUMMY,
                                whichItem: 0,
                                isDodged: false,
                                effectType: EFFECT_REGEN,
                                effectStacks: dummyStatus.regen,
                                player_remaining_health: playerStatus.hp,
                                dummy_remaining_health: dummyStatus.hp,
                                player_stamina: playerStatus.stamina,
                                dummy_stamina: dummyStatus.stamina,
                                player_stacks: (playerStatus.armor, playerStatus.regen, playerStatus.reflect, playerStatus.empower, playerStatus.poison, playerStatus.vampirism),
                                dummy_stacks: (dummyStatus.armor, dummyStatus.regen, dummyStatus.reflect, dummyStatus.empower, dummyStatus.poison, dummyStatus.vampirism),
                            })
                        );
                    }
                }
            };

            battleLog.winner = winner;
            battleLog.seconds = seconds;
            set!(world, (battleLog));

            if winner == PLAYER {
                char.wins += 1;
                char.totalWins += 1;
                char.winStreak += 1;
                char.dummied = false;
                char.gold += 5;
                if char.wins < 5 {
                    char.health += 10;
                } else if char.wins == 5 {
                    char.health += 15;
                }

                char.rating += 25;

                if (dummyChar.rating < 10) {
                    dummyChar.rating = 0;
                } else {
                    dummyChar.rating -= 10;
                }
            } else {
                char.loss += 1;
                char.totalLoss += 1;
                char.winStreak = 0;
                char.gold += 5;

                dummyChar.rating += 25;

                if (char.rating < 10) {
                    char.rating = 0;
                } else {
                    char.rating -= 10;
                }
            }
            char.updatedAt = get_block_timestamp();
            set!(world, (char, dummyChar));
        }
    }

    fn attack(ref world: IWorldDispatcher, ref charStatus: CharStatus, ref opponentStatus: CharStatus, curr_item_belongs: felt252, curr_item_index: u32, item_type: u8, effect_type: u8, effect_stacks: u32, plugins: Span<(u8, usize, usize)>) {
        let mut damageCaused = 0;
        match effect_type {
            0 => {
                assert(false, 'effect type not valid');
            },
            // damage
            1 => {
                let mut damage = effect_stacks;
                // plus empower if item is melee weapon
                if item_type == 1 && charStatus.empower > 0 {
                    damage += charStatus.empower;
                }

                opponentStatus.armor = if opponentStatus.armor > damage {
                    opponentStatus.armor - damage
                } else {
                    damageCaused = damage - opponentStatus.armor;
                    0
                };

                opponentStatus.hp = if opponentStatus.hp > damageCaused {
                    opponentStatus.hp - damageCaused
                } else {
                    0
                };

                battleLogsCount += 1;
                emit!(
                    world,
                    (BattleLogDetail {
                        player,
                        battleLogId: battleLogCounterCount,
                        id: battleLogsCount,
                        whoTriggered: curr_item_belongs,
                        whichItem: curr_item_index,
                        isDodged: false,
                        effectType: effect_type,
                        effectStacks: damageCaused,
                        player_remaining_health: charStatus.hp,
                        dummy_remaining_health: opponentStatus.hp,
                        player_stamina: charStatus.stamina,
                        dummy_stamina: opponentStatus.stamina,
                        player_stacks: (charStatus.armor, charStatus.regen, charStatus.reflect, charStatus.empower, charStatus.poison, charStatus.vampirism),
                        dummy_stacks: (opponentStatus.armor, opponentStatus.regen, opponentStatus.reflect, opponentStatus.empower, opponentStatus.poison, opponentStatus.vampirism),
                    })
                );

                if opponentStatus.hp == 0 {
                    winner = PLAYER;
                    break;
                }
            },
            // Cleanse Poison
            2 => {
                charStatus.poison = if charStatus.poison > effect_stacks {
                    charStatus.poison - effect_stacks
                } else {
                    0
                };
                
                battleLogsCount += 1;
                emit!(
                    world,
                    (BattleLogDetail {
                        player,
                        battleLogId: battleLogCounterCount,
                        id: battleLogsCount,
                        whoTriggered: curr_item_belongs,
                        whichItem: curr_item_index,
                        isDodged: false,
                        effectType: effect_type,
                        effectStacks: effect_stacks,
                        player_remaining_health: charStatus.hp,
                        dummy_remaining_health: opponentStatus.hp,
                        player_stamina: charStatus.stamina,
                        dummy_stamina: opponentStatus.stamina,
                        player_stacks: (charStatus.armor, charStatus.regen, charStatus.reflect, charStatus.empower, charStatus.poison, charStatus.vampirism),
                        dummy_stacks: (opponentStatus.armor, opponentStatus.regen, opponentStatus.reflect, opponentStatus.empower, opponentStatus.poison, opponentStatus.vampirism),
                    })
                );
            },
            // Armor
            3 => {
                charStatus.armor += effect_stacks;
            },
            // Regen
            4 => {
                charStatus.regen += effect_stacks;
            },
            // Reflect
            5 => {
                charStatus.reflect += effect_stacks;
            },
            // Poison
            6 => {
                opponentStatus.poison += effect_stacks;
            },
            // Empower
            7 => {
                charStatus.empower += effect_stacks;
            },
            // Vampirism
            8 => {
                charStatus.vampirism += effect_stacks;
            },
            _ => {
                assert(false, 'effect type not valid');
            },
        }
        
        if effect_type == 1 {
            // ====== dummy reflect ======
            // ====== Reflect effect: Deals 1 damage per stack when hit with a Melee weapon (up to 100% of the damage). ======
            if opponentStatus.reflect > 0 && item_type == 1 && damageCaused > 0 {
                let reflect_damage = if opponentStatus.reflect < damageCaused {
                    opponentStatus.reflect
                } else {
                    damageCaused
                };

                let mut reflectDamageCaused = 0;

                charStatus.armor = if reflect_damage < charStatus.armor {
                    charStatus.armor - reflect_damage
                } else {
                    reflectDamageCaused = reflect_damage - charStatus.armor;
                    0
                };

                charStatus.hp = if charStatus.hp <= reflectDamageCaused {
                    0
                } else {
                    charStatus.hp - reflectDamageCaused;
                }

                battleLogsCount += 1;
                emit!(
                    world,
                    (BattleLogDetail {
                        player,
                        battleLogId: battleLogCounterCount,
                        id: battleLogsCount,
                        whoTriggered: opponent,
                        whichItem: 0,
                        isDodged: false,
                        effectType: EFFECT_REFLECT,
                        effectStacks: reflectDamageCaused,
                        player_remaining_health: charStatus.hp,
                        dummy_remaining_health: opponentStatus.hp,
                        player_stamina: charStatus.stamina,
                        dummy_stamina: opponentStatus.stamina,
                        player_stacks: (charStatus.armor, charStatus.regen, charStatus.reflect, charStatus.empower, charStatus.poison, charStatus.vampirism),
                        dummy_stacks: (opponentStatus.armor, opponentStatus.regen, opponentStatus.reflect, opponentStatus.empower, opponentStatus.poison, opponentStatus.vampirism),
                    })
                );

                if char_health == 0 {
                    winner = DUMMY;
                    break;
                }
            }
            // ====== dummy get hit ======
            let mut on_hit_items_len = dummy_on_hit_items_span.len();
            loop {
                if on_hit_items_len == 0 {
                    break;
                }

                let (
                    on_hit_item_type, on_hit_item_chance, on_hit_item_stack
                ) =
                    *dummy_on_hit_items_span
                    .at(on_hit_items_len - 1);

                if rand < on_hit_item_chance {
                    match on_hit_item_type {
                        0 | 1 => {
                            assert(false, 'effect type not valid');
                        },
                        // Cleanse Poison
                        2 => {
                            opponentStatus.poison = if opponentStatus.poison > on_hit_item_stack {
                                opponentStatus.poison - on_hit_item_stack
                            } else {
                                0
                            };
                            
                            battleLogsCount += 1;
                            emit!(
                                world,
                                (BattleLogDetail {
                                    player,
                                    battleLogId: battleLogCounterCount,
                                    id: battleLogsCount,
                                    whoTriggered: opponent,
                                    whichItem: 0,
                                    isDodged: false,
                                    effectType: on_hit_item_type,
                                    effectStacks: on_hit_item_stack,
                                    player_remaining_health: charStatus.hp,
                                    dummy_remaining_health: opponentStatus.hp,
                                    player_stamina: charStatus.stamina,
                                    dummy_stamina: opponentStatus.stamina,
                                    player_stacks: (charStatus.armor, charStatus.regen, charStatus.reflect, charStatus.empower, charStatus.poison, charStatus.vampirism),
                                    dummy_stacks: (opponentStatus.armor, opponentStatus.regen, opponentStatus.reflect, opponentStatus.empower, opponentStatus.poison, opponentStatus.vampirism),
                                })
                            );
                        },
                        // Armor
                        3 => {
                            opponentStatus.armor += on_hit_item_stack;
                        },
                        // Regen
                        4 => {
                            opponentStatus.regen += on_hit_item_stack;
                        },
                        // Reflect
                        5 => {
                            opponentStatus.reflect += on_hit_item_stack;
                        },
                        // Poison
                        6 => {
                            charStatus.poison += on_hit_item_stack;
                        },
                        // Empower
                        7 => {
                            opponentStatus.empower += on_hit_item_stack;
                        },
                        // Vampirism
                        8 => {
                            opponentStatus.vampirism += on_hit_item_stack;
                        },
                        _ => {
                            assert(false, 'effect type not valid');
                        },
                    }
                }

                on_hit_items_len -= 1;
            };
            // ====== Vampirism effect: Heals HP on Melee Weapon strike equal to amount of stacks, up to 100% of damage done. ======
            if charStatus.vampirism > 0 && item_type == 1 && damageCaused > 0 {
                let vampirism_heal = if charStatus.vampirism < damageCaused {
                    charStatus.vampirism
                } else {
                    damageCaused
                };

                charStatus.hp = if charStatus.hp + vampirism_heal > char_health_flag {
                    char_health_flag
                } else {
                    charStatus.hp + vampirism_heal
                };

                battleLogsCount += 1;
                emit!(
                    world,
                    (BattleLogDetail {
                        player,
                        battleLogId: battleLogCounterCount,
                        id: battleLogsCount,
                        whoTriggered: curr_item_belongs,
                        whichItem: 0,
                        isDodged: false,
                        effectType: EFFECT_VAMPIRISM,
                        effectStacks: vampirism_heal,
                        player_remaining_health: charStatus.hp,
                        dummy_remaining_health: opponentStatus.hp,
                        player_stamina: charStatus.stamina,
                        dummy_stamina: opponentStatus.stamina,
                        player_stacks: (charStatus.armor, charStatus.regen, charStatus.reflect, charStatus.empower, charStatus.poison, charStatus.vampirism),
                        dummy_stacks: (opponentStatus.armor, opponentStatus.regen, opponentStatus.reflect, opponentStatus.empower, opponentStatus.poison, opponentStatus.vampirism),
                    })
                );
            }
            // ====== char on attack ======
            let mut on_attack_items_len = char_on_attack_items_span.len();
            loop {
                if on_attack_items_len == 0 {
                    break;
                }

                let (
                    on_attack_item_type,
                    on_attack_item_chance,
                    on_attack_item_stack
                ) =
                    *char_on_attack_items_span
                    .at(on_attack_items_len - 1);

                if rand < on_attack_item_chance {
                    match on_attack_item_type {
                        0 | 1 => {
                            assert(false, 'effect type not valid');
                        },
                        // Cleanse Poison
                        2 => {
                            charStatus.poison = if charStatus.poison > on_attack_item_stack {
                                charStatus.poison - on_attack_item_stack
                            } else {
                                0
                            };
                            
                            battleLogsCount += 1;
                            emit!(
                                world,
                                (BattleLogDetail {
                                    player,
                                    battleLogId: battleLogCounterCount,
                                    id: battleLogsCount,
                                    whoTriggered: curr_item_belongs,
                                    whichItem: 0,
                                    isDodged: false,
                                    effectType: on_attack_item_type,
                                    effectStacks: on_attack_item_stack,
                                    player_remaining_health: charStatus.hp,
                                    dummy_remaining_health: opponentStatus.hp,
                                    player_stamina: charStatus.stamina,
                                    dummy_stamina: opponentStatus.stamina,
                                    player_stacks: (charStatus.armor, charStatus.regen, charStatus.reflect, charStatus.empower, charStatus.poison, charStatus.vampirism),
                                    dummy_stacks: (opponentStatus.armor, opponentStatus.regen, opponentStatus.reflect, opponentStatus.empower, opponentStatus.poison, opponentStatus.vampirism),
                                })
                            );
                        },
                        // Armor
                        3 => {
                            charStatus.armor += on_attack_item_stack;
                        },
                        // Regen
                        4 => {
                            charStatus.regen += on_attack_item_stack;
                        },
                        // Reflect
                        5 => {
                            charStatus.reflect += on_attack_item_stack;
                        },
                        // Poison
                        6 => {
                            opponentStatus.poison += on_attack_item_stack;
                        },
                        // Empower
                        7 => {
                            charStatus.empower += on_attack_item_stack;
                        },
                        // Vampirism
                        8 => {
                            charStatus.vampirism += on_attack_item_stack;
                        },
                        _ => {
                            assert(false, 'effect type not valid');
                        },
                    }
                }

                on_attack_items_len -= 1;
            };
        }
    }
}
