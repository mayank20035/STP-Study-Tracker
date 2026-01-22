import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { 
  Text, View, StyleSheet, ScrollView, TouchableOpacity, StatusBar, Modal, TextInput, Alert, Platform, Keyboard, ActivityIndicator, FlatList, KeyboardAvoidingView
} from 'react-native';
import { NavigationContainer } from '@react-navigation/native';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { Ionicons } from '@expo/vector-icons';
import { SafeAreaProvider, useSafeAreaInsets } from 'react-native-safe-area-context';
import { StudyProvider, useStudy } from './StudyContext';
import RankingsScreen from './RankingsScreen';
import GrowthScreen from './GrowthScreen';
import ProfileScreen from './ProfileScreen';

// --- HELPER: FORMAT MS TO READABLE TEXT ---
const formatMsToText = (ms: number) => {
  if (!ms) return "0m";
  const hours = Math.floor(ms / 3600000);
  const minutes = Math.floor((ms % 3600000) / 60000);
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m`;
};

const formatTime = (ms: number) => {
  const seconds = Math.floor((ms / 1000) % 60);
  const minutes = Math.floor((ms / (1000 * 60)) % 60);
  const hours = Math.floor((ms / (1000 * 60 * 60)));
  const pad = (n: number) => n < 10 ? `0${n}` : n;
  return `${pad(hours)}:${pad(minutes)}:${pad(seconds)}`;
};

function HomeScreen() {
  const { 
    subjects, logs, addSubject, updateSubject, deleteSubject, isLoading, 
    goals, activeGoalId, setActiveGoalId, addGoal, updateGoal, deleteGoal, 
    theme, isDarkMode, addChapter, updateChapterName, deleteChapter, toggleChapterTimer,
    getDailyTotal, isAnyTimerRunning, getTodayKey,
    homeFilterIds, toggleHomeFilter, moveSubject, updateSubjectNote, toggleChapterHidden,
    categories, updateSubjectCategory, addNewCategory, deleteCategory, editCategory // <--- NEW IMPORTS
  } = useStudy();
  
  const insets = useSafeAreaInsets();
  const [tick, setTick] = useState(0);
  
  useEffect(() => { 
    const interval = setInterval(() => setTick(t => t + 1), 1000); 
    return () => clearInterval(interval); 
  }, []);

  // --- MODAL STATES ---
  const [modalVisible, setModalVisible] = useState(false);
  const [menuVisible, setMenuVisible] = useState(false);
  const [shiftModalVisible, setShiftModalVisible] = useState(false);
  const [detailedHistoryVisible, setDetailedHistoryVisible] = useState(false); 
  const [expandedHistoryDate, setExpandedHistoryDate] = useState<string | null>(null);

  const [expandedSubjects, setExpandedSubjects] = useState<Record<number, boolean>>({});
  const [newChapterNames, setNewChapterNames] = useState<Record<number, string>>({});
  const [filterVisible, setFilterVisible] = useState(false);
  
  const [chapterStatsVisible, setChapterStatsVisible] = useState(false);
  const [selectedSubjectForStats, setSelectedSubjectForStats] = useState<any>(null);
  const [noteText, setNoteText] = useState('');
  
  // --- CATEGORY STATES ---
  const [isAddingCategory, setIsAddingCategory] = useState(false);
  const [newCategoryName, setNewCategoryName] = useState('');
  const [editingCategoryTarget, setEditingCategoryTarget] = useState<string | null>(null); // To track rename

  const [goalModalVisible, setGoalModalVisible] = useState(false);
  const [editingGoalId, setEditingGoalId] = useState<string | null>(null);
  const [goalName, setGoalName] = useState('');
  const [goalHours, setGoalHours] = useState('');
  const [newName, setNewName] = useState('');
  const [newTarget, setNewTarget] = useState('');
  
  // --- OPTIMIZED CALCULATIONS (useMemo) ---
  const totalLiveMs = useMemo(() => {
    const filtered = subjects.filter(s => homeFilterIds.includes(s.id));
    return filtered.reduce((accSub, sub) => {
        const subTotal = sub.chapters.reduce((accChap, chap) => {
            const activeTime = (chap.isRunning && chap.lastStartTime) ? (Date.now() - chap.lastStartTime) : 0;
            return accChap + chap.timeSpent + activeTime;
        }, 0);
        return accSub + subTotal;
    }, 0);
  }, [subjects, homeFilterIds, tick]);

  const totalHours = totalLiveMs / 3600000; 
  const activeGoal = goals.find(g => g.id === activeGoalId);
  const globalGoalTarget = activeGoal ? activeGoal.hours : 1000;
  const rawPercent = globalGoalTarget > 0 ? (totalHours / globalGoalTarget) * 100 : 0;
  const dailyTotalMs = getDailyTotal();
  const todayKey = getTodayKey(); 

  // --- ACTIONS ---
  const toggleExpand = (id: number) => setExpandedSubjects(prev => ({ ...prev, [id]: !prev[id] }));
  
  const openChapterStats = (subject: any) => { 
      setSelectedSubjectForStats(subject); 
      setNoteText(subject.note || ''); 
      setChapterStatsVisible(true); 
      setIsAddingCategory(false); 
      setEditingCategoryTarget(null);
  };

  const handleSaveNote = () => { if (selectedSubjectForStats) { updateSubjectNote(selectedSubjectForStats.id, noteText); Alert.alert("Success", "Note Saved!"); } };
  
  const handleAddCategory = () => {
      if (newCategoryName.trim().length > 0) {
          if (editingCategoryTarget) {
              // EDIT MODE
              editCategory(editingCategoryTarget, newCategoryName.trim());
          } else {
              // ADD MODE
              addNewCategory(newCategoryName.trim());
          }
          setNewCategoryName('');
          setIsAddingCategory(false);
          setEditingCategoryTarget(null);
      }
  };

  const handleLongPressCategory = (category: string) => {
      Alert.alert(
          "Manage Category",
          `What do you want to do with "${category}"?`,
          [
              { text: "Cancel", style: "cancel" },
              { 
                  text: "Rename", 
                  onPress: () => {
                      setEditingCategoryTarget(category);
                      setNewCategoryName(category);
                      setIsAddingCategory(true);
                  } 
              },
              { 
                  text: "Delete", 
                  style: "destructive", 
                  onPress: () => deleteCategory(category) 
              }
          ]
      );
  };

  const handleAddSubject = () => { const t = parseInt(newTarget); if (!newName || isNaN(t)) return; addSubject(newName, t); setNewName(''); setNewTarget(''); setModalVisible(false); };
  const handleAddChapter = (subjectId: number) => { const name = newChapterNames[subjectId]; if (!name || name.trim() === "") return; addChapter(subjectId, name); setNewChapterNames(prev => ({ ...prev, [subjectId]: "" })); };
  const handleDeleteChapter = (subId: number, chapId: string) => { Alert.alert("Delete?", "Remove chapter?", [{ text: "Cancel" }, { text: "Delete", style: 'destructive', onPress: () => deleteChapter(subId, chapId) }]); };
  const handleDeleteSubject = (id: number) => { Alert.alert("Delete Subject?", "This will remove the subject and all its history.", [{ text: "Cancel" }, { text: "Delete", style: 'destructive', onPress: () => deleteSubject(id) }]); };

  const openGoalModal = (goalId: string | null) => { if (goalId) { const g = goals.find(item => item.id === goalId); if (g) { setEditingGoalId(goalId); setGoalName(g.label); setGoalHours(g.hours.toString()); } } else { setEditingGoalId(null); setGoalName(''); setGoalHours(''); } setGoalModalVisible(true); };
  const handleSaveGoal = () => { const h = parseInt(goalHours); if (!goalName || isNaN(h)) return; if (editingGoalId) updateGoal(editingGoalId, goalName, h); else addGoal(goalName, h); setGoalModalVisible(false); };
  const handleDeleteGoal = (id: string) => { if (goals.length <= 1) { Alert.alert("Error", "Keep at least one goal."); return; } Alert.alert("Delete Level?", "Cannot be undone.", [{ text: "Cancel" }, { text: "Delete", style: 'destructive', onPress: () => deleteGoal(id) }]); };

  const getBreakdownForDate = (dateKey: string) => {
      const details: any[] = [];
      subjects.forEach(sub => {
          sub.chapters.forEach(chap => {
              const time = chap.dailyHistory?.[dateKey] || 0;
              if (time > 0) {
                  details.push({
                      subjectName: sub.name,
                      chapterName: chap.name,
                      time: time
                  });
              }
          });
      });
      return details.sort((a, b) => b.time - a.time);
  };

  const ListHeader = useMemo(() => {
    return (
      <View style={[styles.headerCard, { backgroundColor: theme.card, marginTop: 10 }]}>
          <TouchableOpacity style={styles.filterToggleButton} onPress={() => setFilterVisible(!filterVisible)}>
              <Text style={{fontSize: 10, color: theme.textLight, marginRight: 4}}>{filterVisible ? "Hide" : "Filter"}</Text>
              <Ionicons name={filterVisible ? "chevron-up" : "chevron-down"} size={20} color={theme.textLight} />
          </TouchableOpacity>

          <View style={{alignItems: 'center', justifyContent: 'center', marginTop: 10, marginBottom: 5}}>
              <View style={{flexDirection: 'row', alignItems: 'center'}}>
                  <Ionicons name="time" size={28} color={theme.primary} style={{marginRight: 8}} />
                  <Text style={[styles.headerValue, { color: theme.text, fontFamily: Platform.OS === 'ios' ? 'Courier' : 'monospace', fontVariant: ['tabular-nums'], letterSpacing: 2 }]}>
                      {formatTime(totalLiveMs)}
                  </Text>
              </View>
          </View>

          {filterVisible && (
              <View style={[styles.filterListContainer, { borderTopColor: theme.border }]}>
                  <Text style={{color: theme.textLight, fontSize: 12, marginBottom: 8, fontWeight: 'bold'}}>Select subjects to count:</Text>
                  {subjects.map(sub => {
                      const isSelected = homeFilterIds.includes(sub.id);
                      return (
                          <TouchableOpacity 
                            key={sub.id} 
                            style={[styles.filterRow, { backgroundColor: isSelected ? theme.secondary : theme.background }]} 
                            onPress={() => toggleHomeFilter(sub.id)}
                            activeOpacity={0.7}
                          >
                              <Ionicons name={isSelected ? "checkbox" : "square-outline"} size={20} color={isSelected ? theme.primary : theme.textLight} />
                              <Text style={[styles.filterText, { color: isSelected ? theme.primary : theme.textLight }]}>{sub.name}</Text>
                          </TouchableOpacity>
                      );
                  })}
              </View>
          )}

          <View style={[styles.globalGoalContainer, { borderTopColor: theme.border }]}>
              <View style={{flexDirection: 'row', justifyContent: 'space-between', marginBottom: 2}}>
                  <Text style={[styles.goalLabelText, { color: theme.textLight }]}>{activeGoal ? activeGoal.label : "Goal"}</Text>
                  <Text style={[styles.goalLabelText, { color: theme.textLight }]}>{totalHours.toFixed(1)} / {globalGoalTarget} h <Text style={{color: theme.primary}}>({rawPercent.toFixed(2)}%)</Text></Text>
              </View>
              <View style={[styles.globalProgressBarBg, { backgroundColor: theme.background }]}><View style={[styles.globalProgressBarFill, { width: `${Math.min(rawPercent, 100)}%`, backgroundColor: theme.success }]} /></View>
          </View>
      </View>
    );
  }, [filterVisible, subjects, homeFilterIds, totalLiveMs, theme, activeGoal, totalHours, rawPercent]);

  const renderSubjectItem = useCallback(({ item: sub }: { item: any }) => {
    const isExpanded = expandedSubjects[sub.id];
    const subjectDailyMs = sub.chapters.reduce((acc: number, chap: any) => {
        const active = (chap.isRunning && chap.lastStartTime) ? (Date.now() - chap.lastStartTime) : 0;
        const pastDaily = (chap.dailyHistory && chap.dailyHistory[todayKey]) ? chap.dailyHistory[todayKey] : 0;
        return acc + pastDaily + active;
    }, 0);

    return (
        <View style={[styles.card, { backgroundColor: theme.card }]}>
            <TouchableOpacity activeOpacity={0.7} onPress={() => toggleExpand(sub.id)} onLongPress={() => handleDeleteSubject(sub.id)}>
                <View style={styles.cardTopRow}>
                    <View style={{ flex: 1.2, marginRight: 10 }}>
                        <TextInput style={[styles.subjectNameInput, { color: theme.text }]} value={sub.name} onChangeText={(t) => updateSubject(sub.id, 'name', t)} />
                    </View>
                    <View style={{flexDirection: 'row', alignItems: 'center'}}>
                        <View style={[styles.timeBadge, { backgroundColor: theme.secondary }]}>
                            <Text style={{color: theme.primary, fontWeight:'bold', fontSize: 13, fontVariant: ['tabular-nums']}}>{formatTime(subjectDailyMs)}</Text>
                        </View>
                        <View style={[styles.targetBadge, { backgroundColor: theme.background, borderColor: theme.border, borderWidth: 1 }]}>
                            <TextInput style={{color: theme.textLight, fontWeight:'bold', fontSize: 12, minWidth: 20, textAlign: 'center'}} keyboardType="numeric" value={sub.target.toString()} onChangeText={(t) => updateSubject(sub.id, 'target', parseInt(t) || 0)} />
                            <Text style={{color: theme.textLight, fontSize: 10, marginLeft: 1}}>h</Text>
                        </View>
                        <TouchableOpacity onPress={() => openChapterStats(sub)} style={{marginLeft: 8, padding: 4}}>
                            <Ionicons name="information-circle-outline" size={22} color={theme.textLight} />
                        </TouchableOpacity>
                        <Ionicons name={isExpanded ? "chevron-up" : "chevron-down"} size={22} color={theme.textLight} style={{marginLeft: 4}} />
                    </View>
                </View>
            </TouchableOpacity>
            <View style={styles.progressContainer}>
                <View style={[styles.progressBarBg, { backgroundColor: theme.border }]}><View style={[styles.progressBarFill, { width: `${Math.min(sub.progress * 100, 100)}%`, backgroundColor: theme.primary }]} /></View>
                <Text style={{ marginLeft: 10, fontSize: 12, fontWeight: '600', color: theme.textLight }}>{(sub.progress * 100).toFixed(1)}%</Text>
            </View>
            {isExpanded && (
                <View style={{ marginTop: 15 }}>
                    <View style={[styles.divider, { backgroundColor: theme.border }]} />
                    {sub.chapters.map((chapter: any, index: number) => {
                        const active = (chapter.isRunning && chapter.lastStartTime) ? (Date.now() - chapter.lastStartTime) : 0;
                        const pastDaily = (chapter.dailyHistory && chapter.dailyHistory[todayKey]) ? chapter.dailyHistory[todayKey] : 0;
                        const currentDisplayTime = pastDaily + active;
                        const isHidden = chapter.isHidden || false;

                        return (
                            <TouchableOpacity key={chapter.id} activeOpacity={1} style={styles.chapterRow}>
                                <Text style={{color: theme.textLight, fontWeight: 'bold', marginRight: 8, fontSize: 16}}>{index + 1}.</Text>
                                <View style={{flex: 1, marginRight: 10}}><TextInput style={[styles.chapterNameInput, { color: theme.text }]} value={chapter.name} onChangeText={(t) => updateChapterName(sub.id, chapter.id, t)} placeholder="Chapter Name" placeholderTextColor={theme.textLight} /></View>
                                <View style={styles.timerContainer}>
                                    <Text style={[styles.timerText, { color: theme.textLight }]}>
                                        {isHidden ? "###" : formatTime(currentDisplayTime)}
                                    </Text>
                                    <TouchableOpacity onPress={() => toggleChapterTimer(sub.id, chapter.id)} style={[styles.playBtn, { backgroundColor: chapter.isRunning ? theme.danger : theme.success }]}><Ionicons name={chapter.isRunning ? "pause" : "play"} size={14} color="#fff" /></TouchableOpacity>
                                    
                                    <TouchableOpacity 
                                        style={{marginLeft: 10, padding: 4}}
                                        onPress={() => toggleChapterHidden(sub.id, chapter.id)} 
                                        onLongPress={() => handleDeleteChapter(sub.id, chapter.id)}
                                    >
                                        <Ionicons name={isHidden ? "eye-off" : "eye"} size={20} color={theme.textLight} />
                                    </TouchableOpacity>
                                </View>
                            </TouchableOpacity>
                        );
                    })}
                    <View style={[styles.addChapterRow, { backgroundColor: theme.background }]}>
                        <TextInput placeholder="Add Chapter..." placeholderTextColor={theme.textLight} style={[styles.addChapterInput, { color: theme.text }]} value={newChapterNames[sub.id] || ""} onChangeText={(t) => setNewChapterNames(prev => ({...prev, [sub.id]: t}))} />
                        <TouchableOpacity onPress={() => handleAddChapter(sub.id)} style={[styles.smallAddBtn, { backgroundColor: theme.primary }]}><Ionicons name="add" size={20} color="#fff" /></TouchableOpacity>
                    </View>
                </View>
            )}
        </View>
    );
  }, [expandedSubjects, subjects, theme, todayKey, tick, newChapterNames]);

  if (isLoading) return <ActivityIndicator size="large" color={theme.primary} style={styles.centerScreen} />;

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
        <StatusBar barStyle={isDarkMode ? "light-content" : "dark-content"} />
        
        {/* STICKY TOP BAR */}
        <View style={[styles.stickyTopBar, { backgroundColor: theme.card, paddingTop: Math.max(insets.top, 10), height: 60 + Math.max(insets.top, 10) }]}>
            <TouchableOpacity style={{padding: 5}} onPress={() => setMenuVisible(true)}>
                <Ionicons name="menu" size={24} color={theme.text} />
            </TouchableOpacity>
            
            <TouchableOpacity onPress={() => setDetailedHistoryVisible(true)}>
                <View style={[styles.miniTimerCard, { backgroundColor: theme.background }]}>
                    <Ionicons name="stopwatch" size={16} color={isAnyTimerRunning ? theme.primary : theme.textLight} />
                    <Text style={[styles.dailyTimerText, { color: isAnyTimerRunning ? theme.primary : theme.textLight }]}>{formatTime(dailyTotalMs)}</Text>
                    <Ionicons name="chevron-down" size={12} color={theme.textLight} style={{marginLeft: 4}} />
                </View>
            </TouchableOpacity>
        </View>

        {/* --- MAIN LIST --- */}
        <FlatList
            data={subjects}
            renderItem={renderSubjectItem}
            keyExtractor={(item) => item.id.toString()}
            ListHeaderComponent={ListHeader}
            ListFooterComponent={
                <TouchableOpacity style={[styles.addButton, { backgroundColor: theme.primary }]} onPress={() => setModalVisible(true)}>
                    <Ionicons name="add-circle" size={24} color="#fff" />
                    <Text style={styles.addButtonText}>Add New Subject</Text>
                </TouchableOpacity>
            }
            contentContainerStyle={{ paddingBottom: 120, paddingHorizontal: 20 }}
            keyboardDismissMode="on-drag"
            keyboardShouldPersistTaps="handled"
        />

        {/* --- 1. DETAILED HISTORY MODAL --- */}
        <Modal animationType="slide" transparent={true} visible={detailedHistoryVisible} onRequestClose={() => setDetailedHistoryVisible(false)}>
            <View style={styles.modalOverlay}>
                <View style={[styles.modalContent, { backgroundColor: theme.card, height: '85%' }]}>
                    <View style={{flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 15, paddingBottom: 10, borderBottomWidth: 1, borderBottomColor: theme.border}}>
                        <Text style={[styles.modalTitle, { color: theme.text, marginBottom: 0 }]}>⏳ Study History</Text>
                        <TouchableOpacity onPress={() => setDetailedHistoryVisible(false)}>
                            <Ionicons name="close-circle" size={28} color={theme.textLight} />
                        </TouchableOpacity>
                    </View>
                    
                    <FlatList
                        data={Object.entries(logs).sort((a, b) => new Date(b[0]).getTime() - new Date(a[0]).getTime())}
                        keyExtractor={(item) => item[0]}
                        renderItem={({ item }) => {
                            const [date, totalMs] = item;
                            const isExpanded = expandedHistoryDate === date;
                            const breakdown = isExpanded ? getBreakdownForDate(date) : [];

                            return (
                                <View style={{ borderBottomWidth: 1, borderBottomColor: theme.border }}>
                                    <TouchableOpacity 
                                        style={[styles.historyRow, { borderBottomWidth: 0 }]} 
                                        onPress={() => setExpandedHistoryDate(isExpanded ? null : date)}
                                    >
                                        <Text style={{color: theme.text, fontSize: 16, fontWeight: 'bold'}}>{date}</Text>
                                        <View style={{flexDirection: 'row', alignItems: 'center'}}>
                                            <Text style={{color: theme.primary, fontWeight: 'bold', fontSize: 16, marginRight: 8}}>
                                                {formatMsToText(totalMs)}
                                            </Text>
                                            <Ionicons name={isExpanded ? "chevron-up" : "chevron-down"} size={18} color={theme.textLight} />
                                        </View>
                                    </TouchableOpacity>

                                    {isExpanded && (
                                        <View style={{ backgroundColor: theme.background, paddingHorizontal: 10, paddingBottom: 10 }}>
                                            {breakdown.length > 0 ? (
                                                breakdown.map((detail, idx) => (
                                                    <View key={idx} style={{ flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 4 }}>
                                                        <View style={{flex: 1}}>
                                                            <Text style={{color: theme.text, fontSize: 14}}>{detail.chapterName}</Text>
                                                            <Text style={{color: theme.textLight, fontSize: 10}}>{detail.subjectName}</Text>
                                                        </View>
                                                        <Text style={{color: theme.textLight, fontSize: 12}}>{formatMsToText(detail.time)}</Text>
                                                    </View>
                                                ))
                                            ) : (
                                                <Text style={{color: theme.textLight, fontStyle: 'italic', fontSize: 12}}>No specific chapter data.</Text>
                                            )}
                                        </View>
                                    )}
                                </View>
                            );
                        }}
                    />
                </View>
            </View>
        </Modal>

        {/* --- 2. STATS MODAL (UPDATED WITH CATEGORY & KEYBOARD FIX) --- */}
        <Modal animationType="slide" transparent={true} visible={chapterStatsVisible} onRequestClose={() => setChapterStatsVisible(false)}>
            <KeyboardAvoidingView 
                behavior={Platform.OS === "ios" ? "padding" : "height"}
                style={styles.modalOverlay}
            >
                <View style={[styles.modalContent, { backgroundColor: theme.card, maxHeight: '80%' }]}>
                    <View style={{flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10, paddingBottom: 10, borderBottomWidth: 1, borderBottomColor: theme.border}}>
                        <Text style={[styles.modalTitle, { color: theme.text, marginBottom: 0 }]}>{selectedSubjectForStats?.name || "Subject"} Stats</Text>
                        <TouchableOpacity onPress={() => setChapterStatsVisible(false)}><Ionicons name="close-circle" size={28} color={theme.textLight} /></TouchableOpacity>
                    </View>
                    <ScrollView keyboardShouldPersistTaps="handled">
                        
                        {/* --- CATEGORY SECTION --- */}
                        <View style={{marginBottom: 15}}>
                            <Text style={{color: theme.textLight, fontSize: 12, fontWeight: 'bold', marginBottom: 5}}>CATEGORY (Long press to edit)</Text>
                            <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{flexDirection: 'row'}}>
                                {categories.map((cat, index) => {
                                    const isSelected = selectedSubjectForStats?.category === cat;
                                    return (
                                        <TouchableOpacity 
                                            key={index} 
                                            style={[styles.categoryChip, { backgroundColor: isSelected ? theme.primary : theme.background, borderColor: theme.border, borderWidth: 1 }]}
                                            onPress={() => {
                                                updateSubjectCategory(selectedSubjectForStats.id, cat);
                                                setSelectedSubjectForStats({...selectedSubjectForStats, category: cat});
                                            }}
                                            onLongPress={() => handleLongPressCategory(cat)} // <--- LONG PRESS ADDED
                                        >
                                            <Text style={{color: isSelected ? '#fff' : theme.text, fontWeight: '600', fontSize: 12}}>{cat}</Text>
                                        </TouchableOpacity>
                                    );
                                })}
                                <TouchableOpacity 
                                    style={[styles.categoryChip, { backgroundColor: theme.secondary, borderColor: theme.primary, borderWidth: 1 }]}
                                    onPress={() => { setIsAddingCategory(true); setEditingCategoryTarget(null); }}
                                >
                                    <Text style={{color: theme.primary, fontWeight: 'bold', fontSize: 12}}>+ Add</Text>
                                </TouchableOpacity>
                            </ScrollView>

                            {/* Add/Edit Category Input */}
                            {isAddingCategory && (
                                <View style={{flexDirection: 'row', marginTop: 10, alignItems: 'center'}}>
                                    <TextInput 
                                        style={[styles.smallInput, { borderColor: theme.border, color: theme.text, backgroundColor: theme.inputBg, flex: 1, marginRight: 10 }]} // <--- FIXED BG COLOR
                                        placeholder={editingCategoryTarget ? "Rename Category" : "New Category Name"}
                                        placeholderTextColor={theme.textLight}
                                        value={newCategoryName}
                                        onChangeText={setNewCategoryName}
                                        autoFocus
                                    />
                                    <TouchableOpacity onPress={handleAddCategory} style={{backgroundColor: theme.success, padding: 8, borderRadius: 8}}>
                                        <Ionicons name="checkmark" size={18} color="#fff" />
                                    </TouchableOpacity>
                                </View>
                            )}
                        </View>

                        {selectedSubjectForStats?.chapters && selectedSubjectForStats.chapters.length > 0 ? (
                            (() => {
                                const totalSubjectMs = selectedSubjectForStats.chapters.reduce((acc: number, c: any) => acc + c.timeSpent, 0);
                                return [...selectedSubjectForStats.chapters].sort((a: any, b: any) => b.timeSpent - a.timeSpent).map((chap: any, index: number) => {
                                    const percentage = totalSubjectMs > 0 ? (chap.timeSpent / totalSubjectMs) * 100 : 0;
                                    return (
                                        <View key={chap.id} style={[styles.historyRow, { borderBottomColor: theme.border }]}>
                                            <View style={{flexDirection: 'row', alignItems: 'center', flex: 1}}>
                                                <Text style={{fontWeight: 'bold', width: 25, color: index === 0 ? theme.gold : theme.textLight}}>#{index + 1}</Text>
                                                <Text style={{color: theme.text, fontSize: 16, flex: 1}} numberOfLines={1}>{chap.name}</Text>
                                            </View>
                                            <View style={{alignItems: 'flex-end'}}>
                                                <Text style={{color: theme.primary, fontWeight: 'bold', fontSize: 16}}>{(chap.timeSpent / 3600000).toFixed(2)} h</Text>
                                                <Text style={{color: theme.textLight, fontSize: 10}}>{percentage.toFixed(1)}%</Text>
                                            </View>
                                        </View>
                                    );
                                });
                            })()
                        ) : (<Text style={{textAlign: 'center', color: theme.textLight, marginTop: 20}}>No chapters added yet.</Text>)}

                        <View style={{marginTop: 25, borderTopWidth: 1, borderTopColor: theme.border, paddingTop: 15}}>
                            <View style={{flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10}}>
                                <Text style={{color: theme.text, fontWeight: 'bold', fontSize: 16}}>Subject Note</Text>
                                <TouchableOpacity onPress={handleSaveNote} style={{backgroundColor: theme.primary, paddingHorizontal: 12, paddingVertical: 6, borderRadius: 15}}>
                                    <Text style={{color: '#fff', fontSize: 12, fontWeight: 'bold'}}>Save Note</Text>
                                </TouchableOpacity>
                            </View>
                            <TextInput 
                                style={[styles.input, { borderColor: theme.border, color: theme.text, backgroundColor: theme.inputBg, minHeight: 80, textAlignVertical: 'top' }]} 
                                placeholder="Add syllabus, deadlines, or quick notes..." 
                                placeholderTextColor={theme.textLight} 
                                multiline={true}
                                value={noteText}
                                onChangeText={setNoteText}
                            />
                        </View>
                    </ScrollView>
                </View>
            </KeyboardAvoidingView>
        </Modal>

        {/* --- 3. ADD SUBJECT MODAL --- */}
        <Modal animationType="slide" transparent={true} visible={modalVisible} onRequestClose={() => setModalVisible(false)}>
          <View style={styles.modalOverlay}><View style={[styles.modalContent, { backgroundColor: theme.card }]}><Text style={[styles.modalTitle, { color: theme.text }]}>New Subject</Text><TextInput style={[styles.input, { borderColor: theme.border, color: theme.text, backgroundColor: theme.inputBg }]} placeholder="Name" placeholderTextColor={theme.textLight} value={newName} onChangeText={setNewName} /><TextInput style={[styles.input, { borderColor: theme.border, color: theme.text, backgroundColor: theme.inputBg }]} placeholder="Target Hours" placeholderTextColor={theme.textLight} keyboardType="numeric" value={newTarget} onChangeText={setNewTarget} /><View style={styles.modalButtons}><TouchableOpacity style={[styles.modalBtn, { backgroundColor: theme.border }]} onPress={() => setModalVisible(false)}><Text style={[styles.modalBtnText, { color: theme.text }]}>Cancel</Text></TouchableOpacity><TouchableOpacity style={[styles.modalBtn, { backgroundColor: theme.primary }]} onPress={handleAddSubject}><Text style={[styles.modalBtnText, { color: '#fff' }]}>Save</Text></TouchableOpacity></View></View></View>
        </Modal>

        {/* --- 4. MENU MODAL --- */}
        <Modal animationType="fade" transparent={true} visible={menuVisible} onRequestClose={() => setMenuVisible(false)}>
            <TouchableOpacity style={styles.modalOverlay} activeOpacity={1} onPress={() => setMenuVisible(false)}>
                <View style={[styles.menuContent, { backgroundColor: theme.card, maxHeight: '70%' }]}>
                    <Text style={[styles.menuTitle, { color: theme.text }]}>Menu</Text>
                    <ScrollView>
                        <TouchableOpacity 
                            style={[styles.menuRow, { borderBottomColor: theme.border, paddingVertical: 15 }]} 
                            onPress={() => { setMenuVisible(false); setShiftModalVisible(true); }}
                        >
                            <View style={{flexDirection: 'row', alignItems: 'center'}}>
                                <Ionicons name="swap-vertical" size={22} color={theme.primary} />
                                <Text style={[styles.menuOptionTitle, { color: theme.text, marginLeft: 10 }]}>Shift Subjects</Text>
                            </View>
                            <Ionicons name="chevron-forward" size={20} color={theme.textLight} />
                        </TouchableOpacity>

                        <Text style={{color: theme.textLight, marginTop: 15, marginBottom: 5, fontSize: 12, fontWeight: 'bold'}}>LEVELS</Text>
                        {goals.map((goal) => (
                            <View key={goal.id} style={[styles.menuRow, { borderBottomColor: theme.border }]}>
                                <TouchableOpacity style={{flex: 1, flexDirection:'row', alignItems:'center'}} onPress={() => { setActiveGoalId(goal.id); setMenuVisible(false); }}>
                                    <Ionicons name="trophy" size={20} color={theme.primary} />
                                    <View style={{marginLeft: 10}}>
                                        <Text style={[styles.menuOptionTitle, { color: theme.text }]}>{goal.label}</Text>
                                        <Text style={{color: theme.textLight, fontSize: 12}}>{goal.hours} Hours</Text>
                                    </View>
                                </TouchableOpacity>
                                <View style={{flexDirection: 'row', alignItems: 'center'}}>
                                    <TouchableOpacity style={{padding: 8}} onPress={() => openGoalModal(goal.id)}><Ionicons name="pencil" size={18} color={theme.textLight} /></TouchableOpacity>
                                    <TouchableOpacity style={{padding: 8}} onPress={() => handleDeleteGoal(goal.id)}><Ionicons name="trash-outline" size={18} color={theme.danger} /></TouchableOpacity>
                                    <View style={{width: 24, alignItems: 'center'}}>{activeGoalId === goal.id && <Ionicons name="checkmark-circle" size={24} color={theme.success}/>}</View>
                                </View>
                            </View>
                        ))}
                    </ScrollView>
                    <TouchableOpacity style={[styles.addButton, { backgroundColor: theme.primary, marginTop: 15, padding: 12 }]} onPress={() => openGoalModal(null)}><Text style={[styles.addButtonText, { marginLeft: 0 }]}>+ Add New Level</Text></TouchableOpacity>
                </View>
            </TouchableOpacity>
        </Modal>

        {/* --- 5. SHIFT SUBJECTS MODAL --- */}
        <Modal animationType="slide" transparent={true} visible={shiftModalVisible} onRequestClose={() => setShiftModalVisible(false)}>
            <View style={styles.modalOverlay}>
                <View style={[styles.modalContent, { backgroundColor: theme.card, maxHeight: '80%' }]}>
                    <View style={{flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 15, paddingBottom: 10, borderBottomWidth: 1, borderBottomColor: theme.border}}>
                        <Text style={[styles.modalTitle, { color: theme.text, marginBottom: 0 }]}>Reorder Subjects</Text>
                        <TouchableOpacity onPress={() => setShiftModalVisible(false)}>
                            <Ionicons name="close-circle" size={28} color={theme.textLight} />
                        </TouchableOpacity>
                    </View>
                    <Text style={{color: theme.textLight, textAlign: 'center', marginBottom: 15, fontSize: 12}}>Use arrows to shift position.</Text>
                    <FlatList
                        data={subjects}
                        keyExtractor={(item) => item.id.toString()}
                        renderItem={({ item: sub, index }) => (
                            <View style={[styles.filterRow, { backgroundColor: theme.background, justifyContent: 'space-between', paddingVertical: 12, marginBottom: 8 }]}>
                                <Text style={[styles.filterText, { color: theme.text, fontSize: 16 }]}>{sub.name}</Text>
                                <View style={{flexDirection: 'row'}}>
                                    <TouchableOpacity onPress={() => moveSubject(sub.id, 'up')} style={{padding: 5, marginRight: 5, opacity: index === 0 ? 0.3 : 1}} disabled={index === 0}><Ionicons name="arrow-up-circle" size={28} color={theme.primary} /></TouchableOpacity>
                                    <TouchableOpacity onPress={() => moveSubject(sub.id, 'down')} style={{padding: 5, opacity: index === subjects.length - 1 ? 0.3 : 1}} disabled={index === subjects.length - 1}><Ionicons name="arrow-down-circle" size={28} color={theme.primary} /></TouchableOpacity>
                                </View>
                            </View>
                        )}
                    />
                    <TouchableOpacity style={[styles.addButton, { backgroundColor: theme.primary, marginTop: 10 }]} onPress={() => setShiftModalVisible(false)}><Text style={styles.addButtonText}>Done</Text></TouchableOpacity>
                </View>
            </View>
        </Modal>

        {/* --- 6. GOAL MODAL --- */}
        <Modal animationType="slide" transparent={true} visible={goalModalVisible} onRequestClose={() => setGoalModalVisible(false)}>
            <View style={styles.modalOverlay}><View style={[styles.modalContent, { backgroundColor: theme.card }]}><Text style={[styles.modalTitle, { color: theme.text }]}>{editingGoalId ? "Edit Level" : "New Level"}</Text><TextInput style={[styles.input, { borderColor: theme.border, color: theme.text, backgroundColor: theme.inputBg }]} value={goalName} onChangeText={setGoalName} placeholder="Name" /><TextInput style={[styles.input, { borderColor: theme.border, color: theme.text, backgroundColor: theme.inputBg }]} value={goalHours} onChangeText={setGoalHours} keyboardType="numeric" placeholder="Hours" /><View style={styles.modalButtons}><TouchableOpacity style={[styles.modalBtn, { backgroundColor: theme.border }]} onPress={() => setModalVisible(false)}><Text style={[styles.modalBtnText, { color: theme.text }]}>Cancel</Text></TouchableOpacity><TouchableOpacity style={[styles.modalBtn, { backgroundColor: theme.primary }]} onPress={handleSaveGoal}><Text style={[styles.modalBtnText, { color: '#fff' }]}>Save</Text></TouchableOpacity></View></View></View>
        </Modal>
    </View>
  );
}

const Tab = createBottomTabNavigator();

function MainNavigation() {
  const insets = useSafeAreaInsets();
  const { theme } = useStudy(); 
  
  return (
    <Tab.Navigator 
      screenOptions={({ route }) => ({ 
        headerShown: false, 
        tabBarActiveTintColor: theme.primary, 
        tabBarInactiveTintColor: 'gray', 
        tabBarStyle: { 
          height: 60 + (insets.bottom || 10), 
          paddingBottom: insets.bottom || 10, 
          paddingTop: 10, 
          borderTopWidth: 0, 
          backgroundColor: theme.card, 
          elevation: 10 
        }, 
        tabBarIcon: ({ focused, color, size }) => { 
          let iconName: any = 'alert'; 
          if (route.name === 'Home') iconName = focused ? 'home' : 'home-outline'; 
          else if (route.name === 'Rankings') iconName = focused ? 'bar-chart' : 'bar-chart-outline'; 
          else if (route.name === 'Growth') iconName = focused ? 'trending-up' : 'trending-up-outline'; 
          else if (route.name === 'Profile') iconName = focused ? 'person' : 'person-outline'; 
          return <Ionicons name={iconName} size={size} color={color} />; 
        }
      })}
    >
      <Tab.Screen name="Home" component={HomeScreen} />
      <Tab.Screen name="Rankings" component={RankingsScreen} />
      <Tab.Screen name="Growth" component={GrowthScreen} />
      <Tab.Screen name="Profile" component={ProfileScreen} />
    </Tab.Navigator>
  );
}

export default function App() {
  return (
    <SafeAreaProvider>
      <StudyProvider>
        <NavigationContainer independent={true}>
            <MainNavigation />
        </NavigationContainer>
      </StudyProvider>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, paddingTop: 0 }, centerScreen: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  stickyTopBar: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 20, paddingBottom: 10, elevation: 4, zIndex: 10 },
  miniTimerCard: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12, paddingVertical: 6, borderRadius: 20 },
  dailyTimerText: { fontWeight: 'bold', fontSize: 14, marginLeft: 6, fontFamily: Platform.OS === 'ios' ? 'Courier' : 'monospace' },
  headerCard: { padding: 20, borderRadius: 16, marginBottom: 15, elevation: 2 },
  headerValue: { fontSize: 32, fontWeight: 'bold', marginHorizontal: 8, lineHeight: 36 },
  headerUnit: { fontSize: 16, marginBottom: 4 },
  listContainer: { flex: 1 },
  card: { borderRadius: 16, padding: 15, marginBottom: 15, elevation: 2 },
  cardTopRow: { flexDirection: 'row', alignItems: 'center', marginBottom: 10 },
  subjectNameInput: { fontSize: 18, fontWeight: '700', borderBottomWidth: 1, borderBottomColor: 'transparent', padding: 0 },
  timeBadge: { paddingHorizontal: 10, paddingVertical: 5, borderRadius: 8, marginRight: 8 },
  targetBadge: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 8, paddingVertical: 4, borderRadius: 8 },
  progressContainer: { flexDirection: 'row', alignItems: 'center' },
  progressBarBg: { flex: 1, height: 6, borderRadius: 4 },
  progressBarFill: { height: '100%', borderRadius: 4 },
  divider: { height: 1, width: '100%', marginBottom: 10 },
  chapterRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10, paddingVertical: 5 },
  chapterNameInput: { fontSize: 16, borderBottomWidth: 1, borderBottomColor: 'transparent', padding: 0 },
  timerContainer: { flexDirection: 'row', alignItems: 'center' },
  timerText: { fontSize: 14, fontFamily: Platform.OS === 'ios' ? 'Courier' : 'monospace', marginRight: 10 },
  playBtn: { width: 30, height: 30, borderRadius: 15, alignItems: 'center', justifyContent: 'center' },
  addChapterRow: { flexDirection: 'row', alignItems: 'center', borderRadius: 8, padding: 5, marginTop: 5 },
  addChapterInput: { flex: 1, paddingHorizontal: 10, fontSize: 14 },
  smallAddBtn: { width: 30, height: 30, borderRadius: 8, alignItems: 'center', justifyContent: 'center' },
  addButton: { flexDirection: 'row', justifyContent: 'center', alignItems: 'center', padding: 18, borderRadius: 16, marginTop: 10, elevation: 3, marginHorizontal: 20 },
  addButtonText: { color: '#fff', fontSize: 16, fontWeight: 'bold', marginLeft: 10 },
  globalGoalContainer: { width: '100%', marginTop: 10, paddingTop: 10, borderTopWidth: 1 },
  goalLabelText: { fontSize: 12, fontWeight: 'bold' },
  globalProgressBarBg: { height: 6, borderRadius: 3, width: '100%', marginTop: 5 },
  globalProgressBarFill: { height: '100%', borderRadius: 3 },
  modalOverlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.5)', justifyContent: 'center', alignItems: 'center' },
  modalContent: { width: '85%', borderRadius: 20, padding: 20, elevation: 5 },
  modalTitle: { fontSize: 20, fontWeight: 'bold', marginBottom: 15, textAlign: 'center' },
  input: { borderWidth: 1, borderRadius: 10, padding: 12, marginBottom: 15, fontSize: 16 },
  
  // NEW STYLES
  smallInput: { borderWidth: 1, borderRadius: 8, padding: 8, fontSize: 12 },
  categoryChip: { paddingHorizontal: 12, paddingVertical: 6, borderRadius: 15, marginRight: 8, alignItems: 'center', justifyContent: 'center' },

  modalButtons: { flexDirection: 'row', justifyContent: 'space-between' },
  modalBtn: { flex: 1, padding: 12, borderRadius: 10, alignItems: 'center', marginHorizontal: 5 },
  modalBtnText: { fontWeight: 'bold', fontSize: 16 },
  menuContent: { width: '85%', borderRadius: 16, padding: 20, elevation: 5 },
  menuTitle: { fontSize: 20, fontWeight: 'bold', marginBottom: 15, textAlign: 'center' },
  menuRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: 12, borderBottomWidth: 1 },
  menuOptionTitle: { fontSize: 16, fontWeight: 'bold' },
  historyRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 12, borderBottomWidth: 1 },

  // FILTER STYLES
  filterToggleButton: { position: 'absolute', top: 10, right: 10, flexDirection: 'row', alignItems: 'center', zIndex: 5, padding: 5 },
  filterListContainer: { marginTop: 10, marginBottom: 15, borderTopWidth: 1, paddingTop: 10 },
  filterRow: { flexDirection: 'row', alignItems: 'center', padding: 8, borderRadius: 8, marginBottom: 5 },
  filterText: { marginLeft: 10, fontSize: 14, fontWeight: '600' }
});