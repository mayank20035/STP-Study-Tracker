import React, { useState, useMemo } from 'react';
import { 
  View, Text, StyleSheet, ScrollView, TouchableOpacity, Modal 
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useStudy } from './StudyContext';

export default function RankingsScreen() {
  const { subjects, logs, theme, categories } = useStudy();
  const [modalVisible, setModalVisible] = useState(false);
  const [rankingMode, setRankingMode] = useState<'subject' | 'category'>('subject');
  
  const [chapterStatsVisible, setChapterStatsVisible] = useState(false);
  const [selectedSubjectForStats, setSelectedSubjectForStats] = useState<any>(null);

  // --- LOGIC: SUBJECT RANKING ---
  const rankedSubjects = useMemo(() => {
      return [...subjects].sort((a, b) => b.hours - a.hours);
  }, [subjects]);

  // --- LOGIC: CATEGORY RANKING ---
  const rankedCategories = useMemo(() => {
      const catMap: Record<string, number> = {};
      categories.forEach(cat => catMap[cat] = 0);
      catMap['Uncategorized'] = 0;

      subjects.forEach(sub => {
          const cat = sub.category && sub.category !== '' ? sub.category : 'Uncategorized';
          if (catMap[cat] === undefined) catMap[cat] = 0; 
          catMap[cat] += sub.hours;
      });

      return Object.entries(catMap)
          .map(([name, hours]) => ({ name, hours }))
          .filter(item => item.hours > 0) 
          .sort((a, b) => b.hours - a.hours);
  }, [subjects, categories]);

  // --- ACTIONS ---
  const openChapterStats = (subject: any) => {
    setSelectedSubjectForStats(subject);
    setChapterStatsVisible(true);
  };

  const getTopDays = () => {
    const sortedLogs = Object.entries(logs).sort(([, timeA], [, timeB]) => timeB - timeA).slice(0, 3);
    return sortedLogs.map(([date, ms], index) => ({ rank: index + 1, date, hours: ms / 3600000 }));
  };
  const topDays = getTopDays();

  const getRankColor = (rank: number) => {
    if (rank === 1) return '#FFD700'; 
    if (rank === 2) return '#C0C0C0'; 
    if (rank === 3) return '#CD7F32'; 
    return theme.textLight;
  };

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      
      {/* --- FIXED HEADER --- */}
      <View style={[styles.headerCard, { backgroundColor: theme.card }]}>
        
        {/* ROW 1: Label + Button (Now separated properly) */}
        <View style={styles.headerTopRow}>
            <Text style={[styles.headerLabel, { color: theme.textLight }]}>LEADERBOARD</Text>
            
            <TouchableOpacity 
                style={[styles.topDaysBtn, { backgroundColor: theme.secondary }]}
                onPress={() => setModalVisible(true)}
            >
                <Ionicons name="trophy" size={16} color={theme.primary} />
                <Text style={[styles.topDaysText, { color: theme.primary }]}>Best Days</Text>
            </TouchableOpacity>
        </View>
        
        {/* ROW 2: Toggle Switch (Bigger and pushed down) */}
        <View style={styles.toggleRow}>
            <TouchableOpacity onPress={() => setRankingMode('subject')}>
                <Text style={[
                    styles.toggleText, 
                    { 
                        color: rankingMode === 'subject' ? theme.text : theme.textLight,
                        fontSize: rankingMode === 'subject' ? 24 : 18,
                        fontWeight: rankingMode === 'subject' ? 'bold' : 'normal',
                    }
                ]}>Subject</Text>
            </TouchableOpacity>

            <Text style={{color: theme.textLight, marginHorizontal: 15, fontSize: 20}}>|</Text>

            <TouchableOpacity onPress={() => setRankingMode('category')}>
                <Text style={[
                    styles.toggleText, 
                    { 
                        color: rankingMode === 'category' ? theme.text : theme.textLight,
                        fontSize: rankingMode === 'category' ? 24 : 18,
                        fontWeight: rankingMode === 'category' ? 'bold' : 'normal',
                    }
                ]}>Category</Text>
            </TouchableOpacity>
        </View>
        <Text style={{color: theme.textLight, fontSize: 10, marginTop: 5}}>
            {rankingMode === 'subject' ? "Ranked by individual subject hours" : "Ranked by total category hours"}
        </Text>
      </View>

      {/* --- LIST CONTENT --- */}
      <ScrollView contentContainerStyle={{ paddingBottom: 100 }}>
        
        {/* MODE 1: SUBJECT RANKING */}
        {rankingMode === 'subject' && rankedSubjects.map((sub, index) => {
            const currentRank = index + 1;
            const { gold, silver, bronze } = sub.badges;

            return (
              <View key={sub.id} style={[styles.rankCard, { backgroundColor: theme.card }]}>
                
                <View style={styles.rankNumberContainer}>
                    <Text style={[
                        styles.rankNumberText, 
                        { color: currentRank <= 3 ? getRankColor(currentRank) : theme.textLight, fontSize: currentRank <= 3 ? 22 : 16 }
                    ]}>
                        #{currentRank}
                    </Text>
                </View>
                
                <View style={{flex: 1, marginLeft: 15}}>
                    <View style={{flexDirection: 'row', alignItems: 'center'}}>
                        <Text style={[styles.subjectName, { color: theme.text }]}>{sub.name}</Text>
                        <TouchableOpacity onPress={() => openChapterStats(sub)} style={{marginLeft: 6, padding: 2}}>
                             <Ionicons name="information-circle-outline" size={18} color={theme.textLight} />
                        </TouchableOpacity>
                    </View>
                    <Text style={{fontSize: 10, color: theme.textLight, marginBottom: 4}}>
                        {sub.category || "Uncategorized"}
                    </Text>
                    
                    <View style={{flexDirection: 'row', marginBottom: 6}}>
                        {gold > 0 && <View style={[styles.badgePill, { backgroundColor: '#FFF9C4', borderColor: '#FFD700' }]}><Ionicons name="star" size={12} color="#FBC02D" /><Text style={[styles.badgeText, { color: '#F57F17' }]}>{gold}</Text></View>}
                        {silver > 0 && <View style={[styles.badgePill, { backgroundColor: '#F5F5F5', borderColor: '#C0C0C0' }]}><Ionicons name="star" size={12} color="#9E9E9E" /><Text style={[styles.badgeText, { color: '#616161' }]}>{silver}</Text></View>}
                        {bronze > 0 && <View style={[styles.badgePill, { backgroundColor: '#EFEBE9', borderColor: '#CD7F32' }]}><Ionicons name="star" size={12} color="#8D6E63" /><Text style={[styles.badgeText, { color: '#5D4037' }]}>{bronze}</Text></View>}
                    </View>

                    <View style={styles.progressBarBg}>
                        <View style={[styles.progressBarFill, { width: `${Math.min(sub.progress * 100, 100)}%`, backgroundColor: currentRank <= 3 ? getRankColor(currentRank) : theme.primary }]} />
                    </View>
                </View>

                <View style={{alignItems: 'flex-end', minWidth: 60}}>
                    <Text style={[styles.hoursText, { color: theme.text }]}>{sub.hours.toFixed(1)}h</Text>
                    <Text style={{fontSize: 10, color: theme.textLight}}>{(sub.progress * 100).toFixed(0)}%</Text>
                </View>
              </View>
            );
        })}

        {/* MODE 2: CATEGORY RANKING */}
        {rankingMode === 'category' && rankedCategories.map((cat, index) => {
            const currentRank = index + 1;
            const catSubjects = subjects.filter(s => (s.category || 'Uncategorized') === cat.name);
            const totalTarget = catSubjects.reduce((acc, s) => acc + s.target, 0);
            const progress = totalTarget > 0 ? cat.hours / totalTarget : 0;

            return (
              <View key={cat.name} style={[styles.rankCard, { backgroundColor: theme.card }]}>
                <View style={styles.rankNumberContainer}>
                    <Text style={[
                        styles.rankNumberText, 
                        { color: currentRank <= 3 ? getRankColor(currentRank) : theme.textLight, fontSize: currentRank <= 3 ? 22 : 16 }
                    ]}>
                        #{currentRank}
                    </Text>
                </View>
                
                <View style={{flex: 1, marginLeft: 15}}>
                    <Text style={[styles.subjectName, { color: theme.text, fontSize: 18 }]}>{cat.name}</Text>
                    <Text style={{fontSize: 10, color: theme.textLight, marginBottom: 6}}>
                        {catSubjects.length} Subject{catSubjects.length !== 1 ? 's' : ''}
                    </Text>
                    <View style={styles.progressBarBg}>
                        <View style={[styles.progressBarFill, { width: `${Math.min(progress * 100, 100)}%`, backgroundColor: theme.primary }]} />
                    </View>
                </View>

                <View style={{alignItems: 'flex-end', minWidth: 60}}>
                    <Text style={[styles.hoursText, { color: theme.text }]}>{cat.hours.toFixed(1)}h</Text>
                </View>
              </View>
            );
        })}

        {rankingMode === 'subject' && rankedSubjects.length === 0 && <Text style={{textAlign: 'center', color: theme.textLight, marginTop: 50}}>No subjects yet.</Text>}
        {rankingMode === 'category' && rankedCategories.length === 0 && <Text style={{textAlign: 'center', color: theme.textLight, marginTop: 50}}>No data found.</Text>}
      </ScrollView>

      {/* --- HALL OF FAME MODAL --- */}
      <Modal animationType="slide" transparent={true} visible={modalVisible} onRequestClose={() => setModalVisible(false)}>
        <View style={styles.modalOverlay}>
            <View style={[styles.modalContent, { backgroundColor: theme.card }]}>
                <View style={{flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 20}}>
                    <Text style={[styles.modalTitle, { color: theme.text }]}>🏆 Hall of Fame</Text>
                    <TouchableOpacity onPress={() => setModalVisible(false)}><Ionicons name="close-circle" size={28} color={theme.textLight} /></TouchableOpacity>
                </View>
                {topDays.length > 0 ? (
                    topDays.map((day) => (
                        <View key={day.date} style={[styles.bestDayCard, { backgroundColor: theme.background, borderColor: getRankColor(day.rank) }]}>
                            <View style={{flexDirection: 'row', alignItems: 'center'}}>
                                <Ionicons name="medal" size={24} color={getRankColor(day.rank)} />
                                <View style={{marginLeft: 15}}>
                                    <Text style={[styles.bestDayDate, { color: theme.text }]}>{day.date}</Text>
                                    <Text style={{color: getRankColor(day.rank), fontWeight: 'bold', fontSize: 12}}>{day.rank === 1 ? "ALL TIME RECORD" : `Rank #${day.rank}`}</Text>
                                </View>
                            </View>
                            <Text style={[styles.bestDayHours, { color: theme.text }]}>{day.hours.toFixed(1)}h</Text>
                        </View>
                    ))
                ) : <Text style={{textAlign: 'center', color: theme.textLight, padding: 20}}>Start studying to set a record!</Text>}
            </View>
        </View>
      </Modal>

      {/* --- CHAPTER STATS MODAL --- */}
      <Modal animationType="slide" transparent={true} visible={chapterStatsVisible} onRequestClose={() => setChapterStatsVisible(false)}>
            <View style={styles.modalOverlay}>
                <View style={[styles.modalContent, { backgroundColor: theme.card, maxHeight: '60%' }]}>
                    <View style={{flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 15, paddingBottom: 10, borderBottomWidth: 1, borderBottomColor: theme.border}}>
                        <Text style={[styles.modalTitle, { color: theme.text, marginBottom: 0 }]}>
                            {selectedSubjectForStats?.name || "Subject"} Stats
                        </Text>
                        <TouchableOpacity onPress={() => setChapterStatsVisible(false)}>
                            <Ionicons name="close-circle" size={28} color={theme.textLight} />
                        </TouchableOpacity>
                    </View>

                    <ScrollView>
                        {selectedSubjectForStats?.chapters && selectedSubjectForStats.chapters.length > 0 ? (
                            (() => {
                                const totalSubjectMs = selectedSubjectForStats.chapters.reduce((acc: number, c: any) => acc + c.timeSpent, 0);
                                return [...selectedSubjectForStats.chapters]
                                .sort((a: any, b: any) => b.timeSpent - a.timeSpent)
                                .map((chap: any, index: number) => {
                                    const percentage = totalSubjectMs > 0 ? (chap.timeSpent / totalSubjectMs) * 100 : 0;
                                    return (
                                        <View key={chap.id} style={[styles.historyRow, { borderBottomColor: theme.border }]}>
                                            <View style={{flexDirection: 'row', alignItems: 'center', flex: 1}}>
                                                <Text style={{fontWeight: 'bold', width: 25, color: index === 0 ? theme.gold : theme.textLight}}>
                                                    #{index + 1}
                                                </Text>
                                                <Text style={{color: theme.text, fontSize: 16, flex: 1}} numberOfLines={1}>
                                                    {chap.name}
                                                </Text>
                                            </View>
                                            <View style={{alignItems: 'flex-end'}}>
                                                <Text style={{color: theme.primary, fontWeight: 'bold', fontSize: 16}}>
                                                    {(chap.timeSpent / 3600000).toFixed(2)} h
                                                </Text>
                                                <Text style={{color: theme.textLight, fontSize: 10}}>
                                                    {percentage.toFixed(1)}%
                                                </Text>
                                            </View>
                                        </View>
                                    );
                                });
                            })()
                        ) : (
                            <Text style={{textAlign: 'center', color: theme.textLight, marginTop: 20}}>No chapters added yet.</Text>
                        )}
                    </ScrollView>
                </View>
            </View>
      </Modal>

    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, paddingTop: 60, paddingHorizontal: 20 },
  
  // --- UPDATED HEADER STYLES ---
  headerCard: { padding: 20, borderRadius: 16, marginBottom: 20, elevation: 4 },
  headerTopRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 15 },
  headerLabel: { fontSize: 12, fontWeight: '700', letterSpacing: 1 },
  topDaysBtn: { flexDirection: 'row', alignItems: 'center', paddingVertical: 6, paddingHorizontal: 12, borderRadius: 20 },
  topDaysText: { fontWeight: 'bold', marginLeft: 5, fontSize: 12 },
  
  toggleRow: { flexDirection: 'row', alignItems: 'center', marginTop: 5 },
  toggleText: { letterSpacing: 0.5 },

  // --- RANKING LIST STYLES ---
  rankCard: { flexDirection: 'row', alignItems: 'center', padding: 15, borderRadius: 12, marginBottom: 10, elevation: 2 },
  rankNumberContainer: { width: 35, alignItems: 'center', justifyContent: 'center' },
  rankNumberText: { fontWeight: 'bold' },
  subjectName: { fontSize: 16, fontWeight: 'bold', marginBottom: 4 },
  badgePill: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 6, paddingVertical: 2, borderRadius: 8, borderWidth: 1, marginRight: 6 },
  badgeText: { fontSize: 10, fontWeight: 'bold', marginLeft: 3 },
  hoursText: { fontSize: 18, fontWeight: 'bold' },
  progressBarBg: { height: 4, width: '100%', backgroundColor: '#E5E7EB', borderRadius: 2 },
  progressBarFill: { height: '100%', borderRadius: 2 },
  
  // --- MODAL STYLES ---
  modalOverlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.5)', justifyContent: 'center', alignItems: 'center' },
  modalContent: { width: '85%', borderRadius: 20, padding: 20, elevation: 5 },
  modalTitle: { fontSize: 22, fontWeight: 'bold' },
  bestDayCard: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', padding: 15, borderRadius: 12, marginBottom: 10, borderWidth: 1 },
  bestDayDate: { fontSize: 16, fontWeight: 'bold' },
  bestDayHours: { fontSize: 20, fontWeight: 'bold' },
  historyRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 12, borderBottomWidth: 1 }
});