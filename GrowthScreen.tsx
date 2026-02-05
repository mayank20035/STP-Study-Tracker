import React, { useState, useMemo, useEffect } from 'react';
import { 
  View, Text, ScrollView, StyleSheet, Dimensions, TouchableOpacity, Modal 
} from 'react-native';
import { LineChart, ProgressChart } from 'react-native-chart-kit';
import { Calendar } from 'react-native-calendars';
import { Ionicons } from '@expo/vector-icons';
import { useStudy } from './StudyContext';

const screenWidth = Dimensions.get('window').width;

type FilterType = '1W' | '1M' | '1Y';

export default function GrowthScreen() {
  const { logs, theme, getTodayKey, activeGoalId, goals, subjects, homeFilterIds } = useStudy(); 
  
  const [tick, setTick] = useState(0);
  useEffect(() => { 
    const interval = setInterval(() => setTick(t => t + 1), 1000); 
    return () => clearInterval(interval); 
  }, []);

  const [filter, setFilter] = useState<FilterType>('1W');
  const [calendarVisible, setCalendarVisible] = useState(false);
  const [selectedDate, setSelectedDate] = useState(getTodayKey());
  
  const [leaderboardFilterVisible, setLeaderboardFilterVisible] = useState(false);
  const [selectedLeaderboardIds, setSelectedLeaderboardIds] = useState<number[]>([]);

  useEffect(() => {
    if (subjects.length > 0 && selectedLeaderboardIds.length === 0) {
        setSelectedLeaderboardIds(subjects.map(s => s.id));
    }
  }, [subjects.length]);

  const toggleLeaderboardSubject = (id: number) => {
    setSelectedLeaderboardIds(prev => {
        if (prev.includes(id)) return prev.filter(item => item !== id);
        else return [...prev, id];
    });
  };

  const filteredTotalMs = useMemo(() => {
    return subjects.reduce((acc, sub) => {
        if (homeFilterIds.includes(sub.id)) { 
            const subMs = sub.chapters.reduce((cAcc, chap) => {
                const active = (chap.isRunning && chap.lastStartTime) ? (Date.now() - chap.lastStartTime) : 0;
                return cAcc + chap.timeSpent + active;
            }, 0);
            return acc + subMs;
        }
        return acc;
    }, 0);
  }, [subjects, homeFilterIds, tick]);

  const filteredTotalHours = filteredTotalMs / 3600000;
  const activeGoal = goals.find(g => g.id === activeGoalId);
  const targetHours = activeGoal ? activeGoal.hours : 1000;
  const progressPercent = targetHours > 0 ? Math.min(filteredTotalHours / targetHours, 1) : 0;
  const progressData = { labels: ["Total"], data: [progressPercent] };

  const rankedChapters = useMemo(() => {
    const allChapters: any[] = [];
    subjects.forEach(sub => {
        if (selectedLeaderboardIds.includes(sub.id)) { 
            sub.chapters.forEach(chap => {
                const active = (chap.isRunning && chap.lastStartTime) ? (Date.now() - chap.lastStartTime) : 0;
                allChapters.push({
                    ...chap,
                    timeSpent: chap.timeSpent + active, 
                    subjectName: sub.name,
                    subjectColor: sub.color || theme.primary
                });
            });
        }
    });
    return allChapters.sort((a, b) => b.timeSpent - a.timeSpent);
  }, [subjects, selectedLeaderboardIds, tick]);

  // --- CHART DATA ENGINE ---
  const chartDataInfo = useMemo(() => {
    const labels: string[] = [];
    const data: number[] = [];
    const today = new Date();
    let totalPeriodHours = 0;
    let daysCount = 0;

    if (filter === '1W') {
      daysCount = 7;
      for (let i = 6; i >= 0; i--) {
        const d = new Date();
        d.setDate(today.getDate() - i);
        const key = d.toISOString().split('T')[0];
        const val = logs[key] ? logs[key] / 3600000 : 0;
        labels.push(d.toLocaleDateString('en-US', { weekday: 'short' }));
        data.push(val);
        totalPeriodHours += val;
      }
    } 
    else if (filter === '1M') {
      daysCount = 28; // Approx 4 weeks
      for (let i = 3; i >= 0; i--) {
        let weeklySum = 0;
        const startDay = i * 7; 
        for (let j = 0; j < 7; j++) {
            const d = new Date();
            d.setDate(today.getDate() - (startDay + j));
            const key = d.toISOString().split('T')[0];
            weeklySum += (logs[key] || 0);
        }
        const val = weeklySum / 3600000;
        labels.push(`W${4 - i}`);
        data.push(val);
        totalPeriodHours += val;
      }
    } 
    else if (filter === '1Y') {
      daysCount = 180; // Approx 6 months
      for (let i = 5; i >= 0; i--) {
        const d = new Date();
        d.setMonth(today.getMonth() - i);
        const monthKey = d.toISOString().slice(0, 7);
        const monthlySum = Object.keys(logs)
            .filter(key => key.startsWith(monthKey))
            .reduce((sum, key) => sum + logs[key], 0);
        const val = monthlySum / 3600000;
        labels.push(d.toLocaleDateString('en-US', { month: 'short' }));
        data.push(val);
        totalPeriodHours += val;
      }
    }

    // Calculate Average
    const average = totalPeriodHours / (filter === '1W' ? 7 : filter === '1M' ? 30 : 180); // Divider based on days approx

    // Calculate Trophy Data (Top 3 Highest Points in this period)
    const sortedData = [...data].sort((a, b) => b - a).slice(0, 3);

    return { 
        chart: { labels, datasets: [{ data }] },
        average: average,
        top3: sortedData
    };
  }, [filter, logs]);

  const getDayStyle = (ms: number) => {
    const hours = ms / 3600000;
    if (hours >= 10) return { bg: '#FFD700', text: '#000', opacity: 1, border: '#FFD700' };
    if (hours >= 6) return { bg: '#312E81', text: '#FFF', opacity: 1 };
    if (hours >= 3) return { bg: '#4F46E5', text: '#FFF', opacity: 0.8 };
    if (hours > 0) return { bg: '#A5B4FC', text: '#000', opacity: 1 };
    return { bg: 'transparent', text: theme.text, opacity: 0.3 };
  };

  const renderCustomDay = ({ date, state }: { date: any, state: any }) => {
    const dateStr = date.dateString;
    const ms = logs[dateStr] || 0;
    const hours = ms / 3600000;
    const styleInfo = getDayStyle(ms);
    const isSelected = dateStr === selectedDate;

    return (
        <TouchableOpacity 
            onPress={() => setSelectedDate(dateStr)}
            style={[
                styles.dayContainer, 
                { 
                    backgroundColor: styleInfo.bg,
                    borderColor: isSelected ? theme.text : (styleInfo.border || 'transparent'),
                    borderWidth: isSelected ? 2 : (styleInfo.border ? 1 : 0),
                    opacity: state === 'disabled' ? 0.3 : 1
                }
            ]}
        >
            <Text style={{ color: styleInfo.text, fontWeight: 'bold', fontSize: 14 }}>{date.day}</Text>
            {hours > 0 && <Text style={{ color: styleInfo.text, fontSize: 8, marginTop: 0, fontWeight: 'bold' }}>{hours.toFixed(1)}h</Text>}
        </TouchableOpacity>
    );
  };

  const chartConfig = {
    backgroundGradientFrom: theme.card,
    backgroundGradientTo: theme.card,
    color: (opacity = 1) => `rgba(${theme.id === 'dark' ? '129, 140, 248' : '79, 70, 229'}, ${opacity})`,
    strokeWidth: 2, 
    decimalPlaces: 0, 
    labelColor: (opacity = 1) => theme.text,
    propsForDots: { r: "5", strokeWidth: "2", stroke: theme.primary }
  };

  const FilterBtn = ({ type, label }: { type: FilterType, label: string }) => (
    <TouchableOpacity 
        style={[styles.filterBtn, filter === type ? { backgroundColor: theme.card, elevation: 2 } : {}]}
        onPress={() => setFilter(type)}
    >
        <Text style={[styles.filterText, filter === type ? { color: theme.primary } : { color: theme.textLight }]}>{label}</Text>
    </TouchableOpacity>
  );

  return (
    <ScrollView style={[styles.container, { backgroundColor: theme.background }]} contentContainerStyle={{ paddingBottom: 120 }}>
      
      {/* HEADER */}
      <View style={[styles.headerCard, { backgroundColor: theme.card }]}>
        <TouchableOpacity style={styles.calendarButton} onPress={() => setCalendarVisible(true)}>
            <Ionicons name="calendar" size={24} color={theme.text} />
        </TouchableOpacity>
        <Text style={[styles.headerLabel, { color: theme.textLight }]}>ANALYTICS</Text>
        <Text style={[styles.headerValue, { color: theme.text }]}>Consistency</Text>
      </View>

      {/* LINE CHART & AVERAGE */}
      <View style={[styles.card, { backgroundColor: theme.card }]}>
        
        {/* Header Row */}
        <View style={styles.cardHeaderRow}>
            <Text style={[styles.cardTitle, { color: theme.text }]}>Study History</Text>
            <View style={[styles.filterContainer, { backgroundColor: theme.background }]}>
                <FilterBtn type="1W" label="1W" />
                <FilterBtn type="1M" label="1M" />
                <FilterBtn type="1Y" label="1Y" />
            </View>
        </View>

        {/* Chart */}
        <LineChart
            data={chartDataInfo.chart}
            width={screenWidth - 50}
            height={220}
            chartConfig={chartConfig}
            bezier
            style={{ borderRadius: 16, paddingRight: 40, marginTop: 10 }}
            fromZero={true}
        />

        {/* --- NEW: AVERAGE & TROPHY SECTION --- */}
        <View style={[styles.averageContainer, { borderTopColor: theme.border }]}>
            <View style={{alignItems: 'flex-start'}}>
                <Text style={{color: theme.textLight, fontSize: 12, fontWeight: 'bold'}}>
                    {filter === '1W' ? 'WEEKLY' : filter === '1M' ? 'MONTHLY' : 'YEARLY'} AVERAGE
                </Text>
                <Text style={{color: theme.primary, fontSize: 22, fontWeight: 'bold'}}>
                    {chartDataInfo.average.toFixed(1)} <Text style={{fontSize: 14}}>hrs/day</Text>
                </Text>
            </View>

            <View style={{alignItems: 'flex-end'}}>
                <View style={{flexDirection: 'row', alignItems: 'center', marginBottom: 4}}>
                    <Ionicons name="trophy" size={16} color="#FFD700" />
                    <Text style={{color: theme.text, fontWeight: 'bold', marginLeft: 4}}>Top Highs</Text>
                </View>
                <View style={{flexDirection: 'row'}}>
                    {chartDataInfo.top3.map((val, idx) => (
                        val > 0 && (
                            <View key={idx} style={[styles.miniBadge, { backgroundColor: idx === 0 ? '#FFF9C4' : theme.background }]}>
                                <Text style={{fontSize: 10, color: theme.text, fontWeight: 'bold'}}>{val.toFixed(0)}h</Text>
                            </View>
                        )
                    ))}
                </View>
            </View>
        </View>

      </View>

      {/* PROGRESS RING */}
      <View style={[styles.card, { backgroundColor: theme.card }]}>
        <Text style={[styles.cardTitle, { color: theme.text }]}>Goal Completion</Text>
        <View style={{ alignItems: 'center' }}>
            <ProgressChart
                data={progressData}
                width={screenWidth - 60}
                height={150}
                strokeWidth={16}
                radius={32}
                chartConfig={{ ...chartConfig, color: (opacity = 1) => `rgba(16, 185, 129, ${opacity})` }}
                hideLegend={false}
            />
            <Text style={{color: theme.textLight, marginTop: 10}}>
                 {filteredTotalHours.toFixed(2)} / {targetHours} Hours
            </Text>
            <Text style={{fontSize: 10, color: theme.textLight, fontStyle: 'italic'}}>(Based on Home Screen Filter)</Text>
        </View>
      </View>

      {/* CHAPTER RANKINGS */}
      <View style={[styles.card, { backgroundColor: theme.card }]}>
        <View style={{flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 15, zIndex: 10}}>
            <View style={{flexDirection: 'row', alignItems: 'center'}}>
                <Text style={{fontSize: 20, marginRight: 5}}>🏆</Text>
                <Text style={[styles.cardTitle, { color: theme.text, fontSize: 16 }]}>Chapter Rankings</Text>
            </View>
            <TouchableOpacity style={styles.filterToggleButton} onPress={() => setLeaderboardFilterVisible(!leaderboardFilterVisible)}>
                <Text style={{fontSize: 10, color: theme.textLight, marginRight: 4}}>{leaderboardFilterVisible ? "Hide Filters" : "Filter Subjects"}</Text>
                <Ionicons name={leaderboardFilterVisible ? "chevron-up" : "chevron-down"} size={16} color={theme.textLight} />
            </TouchableOpacity>
        </View>

        {leaderboardFilterVisible && (
            <View style={[styles.filterListContainer, { borderBottomColor: theme.border }]}>
                <Text style={{color: theme.textLight, fontSize: 10, marginBottom: 5, fontStyle:'italic'}}>
                    Tap to include/exclude (Rankings Only):
                </Text>
                <ScrollView style={{maxHeight: 120}} nestedScrollEnabled={true}>
                    {subjects.map(sub => {
                        const isSelected = selectedLeaderboardIds.includes(sub.id); 
                        return (
                            <TouchableOpacity key={sub.id} style={[styles.filterRow, { backgroundColor: isSelected ? theme.secondary : theme.background }]} onPress={() => toggleLeaderboardSubject(sub.id)}>
                                <Ionicons name={isSelected ? "checkbox" : "square-outline"} size={20} color={isSelected ? theme.primary : theme.textLight} />
                                <Text style={[styles.filterText, { color: isSelected ? theme.primary : theme.textLight }]}>{sub.name}</Text>
                            </TouchableOpacity>
                        );
                    })}
                </ScrollView>
            </View>
        )}

        <View style={{maxHeight: 300}}>
            {rankedChapters.length > 0 ? (
                rankedChapters.slice(0, 5).map((chap, index) => (
                    <View key={index} style={[styles.rankRow, { borderBottomColor: theme.border }]}>
                        <View style={{width: 30, alignItems: 'center'}}>
                            {index === 0 ? <Text style={{fontSize: 16}}>🥇</Text> : 
                             index === 1 ? <Text style={{fontSize: 16}}>🥈</Text> : 
                             index === 2 ? <Text style={{fontSize: 16}}>🥉</Text> : 
                             <Text style={{color: theme.textLight, fontWeight: 'bold'}}>#{index + 1}</Text>}
                        </View>
                        <View style={{flex: 1, marginLeft: 10}}>
                            <Text style={{color: theme.text, fontWeight: index === 0 ? 'bold' : 'normal', fontSize: 15}} numberOfLines={1}>{chap.name}</Text>
                            <Text style={{color: theme.textLight, fontSize: 10}}>{chap.subjectName}</Text>
                        </View>
                        <Text style={{color: index === 0 ? theme.primary : theme.textLight, fontWeight: 'bold'}}>{(chap.timeSpent / 3600000).toFixed(1)}h</Text>
                    </View>
                ))
            ) : (<Text style={{color: theme.textLight, fontStyle: 'italic', textAlign: 'center', padding: 20}}>No chapters selected.</Text>)}
        </View>
      </View>

      {/* CALENDAR MODAL */}
      <Modal animationType="slide" transparent={true} visible={calendarVisible} onRequestClose={() => setCalendarVisible(false)}>
        <View style={styles.modalOverlay}>
            <View style={[styles.modalContent, { backgroundColor: theme.card, height: '70%' }]}>
                <View style={{flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 20}}>
                    <Text style={[styles.modalTitle, { color: theme.text, marginBottom: 0 }]}>Growth Calendar</Text>
                    <TouchableOpacity onPress={() => setCalendarVisible(false)}><Ionicons name="close-circle" size={28} color={theme.textLight} /></TouchableOpacity>
                </View>
                <Calendar
                    theme={{
                        backgroundColor: theme.card,
                        calendarBackground: theme.card,
                        textSectionTitleColor: theme.textLight,
                        monthTextColor: theme.text,
                        arrowColor: theme.primary,
                        dayTextColor: theme.text,
                    }}
                    markingType={'custom'} 
                    dayComponent={({date, state}: any) => renderCustomDay({date, state})}
                />
                <View style={[styles.statsBox, { backgroundColor: theme.background }]}>
                    <Text style={{color: theme.textLight, marginBottom: 5}}>Selected Date:</Text>
                    <Text style={{color: theme.primary, fontSize: 24, fontWeight: 'bold'}}>{selectedDate}</Text>
                    <Text style={{color: theme.text, fontSize: 16}}>Studied: <Text style={{fontWeight:'bold'}}>{(logs[selectedDate] ? logs[selectedDate]/3600000 : 0).toFixed(1)}h</Text></Text>
                </View>
            </View>
        </View>
      </Modal>

    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, paddingTop: 60, paddingHorizontal: 20 },
  headerCard: { padding: 20, borderRadius: 16, marginBottom: 25, elevation: 4, alignItems: 'center' },
  headerLabel: { fontSize: 14, fontWeight: '600', marginBottom: 5, letterSpacing: 1 },
  headerValue: { fontSize: 32, fontWeight: 'bold' },
  calendarButton: { position: 'absolute', top: 20, right: 20, padding: 5 },
  card: { borderRadius: 16, padding: 16, marginBottom: 20, elevation: 2 },
  cardHeaderRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', width: '100%' },
  cardTitle: { fontSize: 18, fontWeight: 'bold' },
  filterContainer: { flexDirection: 'row', borderRadius: 8, padding: 2 },
  filterBtn: { paddingVertical: 4, paddingHorizontal: 12, borderRadius: 6 },
  filterText: { fontSize: 12, fontWeight: '600' },
  
  // NEW: AVERAGE STYLES
  averageContainer: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginTop: 20, paddingTop: 15, borderTopWidth: 1 },
  miniBadge: { paddingHorizontal: 6, paddingVertical: 2, borderRadius: 6, borderWidth: 1, borderColor: '#DDD', marginRight: 4 },

  modalOverlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.5)', justifyContent: 'center', alignItems: 'center' },
  modalContent: { width: '95%', borderRadius: 20, padding: 15, elevation: 5 },
  modalTitle: { fontSize: 20, fontWeight: 'bold' },
  statsBox: { marginTop: 20, padding: 20, borderRadius: 12, alignItems: 'center' },
  dayContainer: { width: 45, height: 45, alignItems: 'center', justifyContent: 'center', borderRadius: 8, margin: -1 },
  filterToggleButton: { flexDirection: 'row', alignItems: 'center', padding: 5, backgroundColor: 'rgba(0,0,0,0.05)', borderRadius: 12, paddingHorizontal: 10 },
  filterListContainer: { marginTop: 5, borderBottomWidth: 1, paddingBottom: 10, marginBottom: 10 },
  filterRow: { flexDirection: 'row', alignItems: 'center', padding: 8, borderRadius: 8, marginBottom: 5 },
  filterText: { marginLeft: 10, fontSize: 14, fontWeight: '600' },
  rankRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 10, borderBottomWidth: 1 }
});