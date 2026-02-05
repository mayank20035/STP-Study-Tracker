import React, { useState, useEffect, createContext, useContext } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { subDays, format, isAfter, parseISO } from 'date-fns';
import { Alert } from 'react-native';
// --- FIX: IMPORT FROM LEGACY TO SOLVE CRASH ---
import * as FileSystem from 'expo-file-system/legacy'; 
import * as Sharing from 'expo-sharing';
import * as DocumentPicker from 'expo-document-picker';

export const APP_THEME = {
  light: { id: 'light', background: '#F3F4F6', card: '#FFFFFF', text: '#1F2937', textLight: '#6B7280', primary: '#4F46E5', secondary: '#E0E7FF', danger: '#EF4444', gold: '#FFD700', border: '#E5E7EB', inputBg: '#FFFFFF', success: '#10B981' },
  dark: { id: 'dark', background: '#111827', card: '#1F2937', text: '#F9FAFB', textLight: '#9CA3AF', primary: '#818CF8', secondary: '#312E81', danger: '#F87171', gold: '#FFD700', border: '#374151', inputBg: '#374151', success: '#34D399' }
};

export type Badges = { gold: number; silver: number; bronze: number; };
export type DailyLog = Record<string, number>; 
export type GoalOption = { id: string; label: string; hours: number; };

export type Chapter = { 
    id: string; 
    name: string; 
    timeSpent: number; 
    dailyHistory: Record<string, number>; 
    isRunning: boolean; 
    lastStartTime: number | null;
    isHidden?: boolean; 
};

export type Subject = {
  id: number; name: string; hours: number; target: number; progress: number; 
  badges: Badges;
  chapters: Chapter[];
  note?: string; 
  category?: string; 
};

type StudyContextType = {
  subjects: Subject[]; logs: DailyLog; goals: GoalOption[]; activeGoalId: string;
  categories: string[]; 
  theme: typeof APP_THEME.light; isDarkMode: boolean; isLoading: boolean;
  homeFilterIds: number[]; 
  setActiveGoalId: (id: string) => void; addGoal: (l: string, h: number) => void; updateGoal: (id: string, l: string, h: number) => void; deleteGoal: (id: string) => void;
  toggleTheme: () => void; addSubject: (n: string, t: number) => void; updateSubject: (id: number, f: keyof Subject, v: string | number) => void; deleteSubject: (id: number) => void;
  addChapter: (sId: number, cName: string) => void; updateChapterName: (sId: number, cId: string, n: string) => void; deleteChapter: (sId: number, cId: string) => void; toggleChapterTimer: (sId: number, cId: string) => void;
  toggleHomeFilter: (id: number) => void; 
  moveSubject: (id: number, direction: 'up' | 'down') => void;
  updateSubjectNote: (id: number, note: string) => void; 
  toggleChapterHidden: (sId: number, cId: string) => void; 
  updateSubjectCategory: (id: number, category: string) => void; 
  addNewCategory: (category: string) => void;
  deleteCategory: (category: string) => void;
  editCategory: (oldName: string, newName: string) => void;
  exportData: () => Promise<void>; 
  importData: () => Promise<void>; 
  getTodayKey: () => string; getDailyTotal: () => number; isAnyTimerRunning: boolean;
};

const StudyContext = createContext<StudyContextType | undefined>(undefined);

export function StudyProvider({ children }: { children: React.ReactNode }) {
  const [subjects, setSubjects] = useState<Subject[]>([]);
  const [logs, setLogs] = useState<DailyLog>({});
  const [goals, setGoals] = useState<GoalOption[]>([{ id: '1', label: 'Beginner', hours: 1000 }, { id: '2', label: 'Intermediate', hours: 5000 }, { id: '3', label: 'Expert', hours: 10000 }]);
  const [categories, setCategories] = useState<string[]>(['Entertainment', 'Exam Prep', 'Workout']);
  
  const [activeGoalId, setActiveGoalId] = useState<string>('1');
  const [isDarkMode, setIsDarkMode] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  
  const [homeFilterIds, setHomeFilterIds] = useState<number[]>([]);

  const theme = isDarkMode ? APP_THEME.dark : APP_THEME.light;

  const getTodayKey = () => {
    const now = new Date();
    if (now.getHours() < 5) return format(subDays(now, 1), 'yyyy-MM-dd');
    return format(now, 'yyyy-MM-dd');
  };

  const toggleHomeFilter = (id: number) => {
    setHomeFilterIds(prev => {
        if (prev.includes(id)) return prev.filter(item => item !== id);
        else return [...prev, id];
    });
  };

  const moveSubject = (id: number, direction: 'up' | 'down') => {
    setSubjects(prev => {
        const index = prev.findIndex(s => s.id === id);
        if (index === -1) return prev;
        const newSubjects = [...prev];
        if (direction === 'up' && index > 0) {
            [newSubjects[index], newSubjects[index - 1]] = [newSubjects[index - 1], newSubjects[index]];
        } else if (direction === 'down' && index < newSubjects.length - 1) {
            [newSubjects[index], newSubjects[index + 1]] = [newSubjects[index + 1], newSubjects[index]];
        }
        return newSubjects;
    });
  };

  const updateSubjectNote = (id: number, note: string) => {
      setSubjects(prev => prev.map(s => s.id === id ? { ...s, note: note } : s));
  };

  const updateSubjectCategory = (id: number, category: string) => {
      setSubjects(prev => prev.map(s => s.id === id ? { ...s, category: category } : s));
  };

  const addNewCategory = (category: string) => {
      if (!category || categories.includes(category)) return;
      setCategories(prev => [...prev, category]);
  };

  const deleteCategory = (categoryName: string) => {
      setCategories(prev => prev.filter(c => c !== categoryName));
      setSubjects(prev => prev.map(s => s.category === categoryName ? { ...s, category: '' } : s));
  };

  const editCategory = (oldName: string, newName: string) => {
      if (!newName || categories.includes(newName)) return;
      setCategories(prev => prev.map(c => c === oldName ? newName : c));
      setSubjects(prev => prev.map(s => s.category === oldName ? { ...s, category: newName } : s));
  };

  const toggleChapterHidden = (subjectId: number, chapterId: string) => {
      setSubjects(prev => prev.map(sub => {
          if (sub.id !== subjectId) return sub;
          return {
              ...sub,
              chapters: sub.chapters.map(chap => {
                  if (chap.id !== chapterId) return chap;
                  return { ...chap, isHidden: !chap.isHidden };
              })
          };
      }));
  };

  // --- EXPORT FUNCTION ---
  const exportData = async () => {
    try {
        const isAvailable = await Sharing.isAvailableAsync();
        if (!isAvailable) {
            Alert.alert("Error", "Sharing is not available on this device.");
            return;
        }

        const data = {
            subjects,
            logs,
            goals,
            categories,
            activeGoalId,
            isDarkMode,
            timestamp: new Date().toISOString(),
            version: '1.1.0'
        };

        const fileUri = FileSystem.documentDirectory + 'STP_Backup.json';
        await FileSystem.writeAsStringAsync(fileUri, JSON.stringify(data));

        await Sharing.shareAsync(fileUri, {
            mimeType: 'application/json',
            dialogTitle: 'Save STP Backup',
            UTI: 'public.json'
        });
    } catch (error) {
        Alert.alert("Export Failed", `Reason: ${error}`);
    }
  };

  // --- IMPORT FUNCTION ---
  const importData = async () => {
    try {
        const result = await DocumentPicker.getDocumentAsync({ type: 'application/json' });
        
        if (result.assets && result.assets[0]) {
            const fileContent = await FileSystem.readAsStringAsync(result.assets[0].uri);
            const parsed = JSON.parse(fileContent);

            if (!parsed.subjects || !parsed.logs || !parsed.categories) {
                Alert.alert("Invalid File", "This file does not contain valid STP data.");
                return;
            }

            setSubjects(parsed.subjects);
            setLogs(parsed.logs);
            setGoals(parsed.goals);
            setCategories(parsed.categories);
            setActiveGoalId(parsed.activeGoalId);
            setIsDarkMode(parsed.isDarkMode);

            await AsyncStorage.setItem('@study_data', JSON.stringify(parsed.subjects));
            await AsyncStorage.setItem('@study_logs', JSON.stringify(parsed.logs));
            await AsyncStorage.setItem('@user_categories', JSON.stringify(parsed.categories));
            await AsyncStorage.setItem('@user_goals', JSON.stringify(parsed.goals));
            
            Alert.alert("Success", "Data imported successfully!");
        }
    } catch (error) {
        Alert.alert("Import Failed", "Could not read the file.");
    }
  };

  const checkDailyBadges = async (currentSubjects: Subject[]) => {
    const today = getTodayKey();
    const lastCheck = await AsyncStorage.getItem('@last_badge_check');

    if (lastCheck !== today && currentSubjects.length > 0) {
        const sorted = [...currentSubjects].sort((a, b) => b.hours - a.hours);
        const updatedSubjects = currentSubjects.map(sub => {
            const rank = sorted.findIndex(s => s.id === sub.id); 
            const newBadges = { ...sub.badges };
            if (rank === 0) newBadges.gold += 1;
            else if (rank === 1) newBadges.silver += 1;
            else if (rank === 2) newBadges.bronze += 1;
            return { ...sub, badges: newBadges };
        });
        setSubjects(updatedSubjects);
        await AsyncStorage.setItem('@last_badge_check', today);
        await AsyncStorage.setItem('@study_data', JSON.stringify(updatedSubjects));
    }
  };

  const pruneOldLogs = (currentLogs: DailyLog) => {
      const cutoffDate = subDays(new Date(), 30);
      const newLogs: DailyLog = {};
      let changed = false;
      Object.keys(currentLogs).forEach(dateStr => {
          if (isAfter(parseISO(dateStr), cutoffDate)) {
              newLogs[dateStr] = currentLogs[dateStr];
          } else {
              changed = true;
          }
      });
      return changed ? newLogs : currentLogs;
  };

  useEffect(() => {
    (async () => {
      try {
        const [sub, log, thm, gol, act, savedFilter, savedCats] = await Promise.all([
            AsyncStorage.getItem('@study_data'), 
            AsyncStorage.getItem('@study_logs'), 
            AsyncStorage.getItem('@is_dark_mode'), 
            AsyncStorage.getItem('@user_goals'), 
            AsyncStorage.getItem('@active_goal_id'),
            AsyncStorage.getItem('@home_filter_ids'),
            AsyncStorage.getItem('@user_categories') 
        ]);
        
        let loadedSubjects = [];
        if (sub) {
            loadedSubjects = JSON.parse(sub).map((s:any)=>({
                ...s, 
                badges: s.badges || {gold:0, silver:0, bronze:0},
                chapters: (s.chapters||[]).map((c: any) => ({ 
                    ...c, 
                    dailyHistory: c.dailyHistory || {},
                    isHidden: c.isHidden || false
                })),
                note: s.note || '',
                category: s.category || ''
            }));
            setSubjects(loadedSubjects);
            
            if (savedFilter) {
                const parsedFilter = JSON.parse(savedFilter);
                const validIds = parsedFilter.filter((id: number) => loadedSubjects.some((s: any) => s.id === id));
                if (parsedFilter.length === 0 && savedFilter !== null) setHomeFilterIds([]);
                else if (validIds.length > 0) setHomeFilterIds(validIds);
                else setHomeFilterIds(loadedSubjects.map((s: any) => s.id));
            } else {
                setHomeFilterIds(loadedSubjects.map((s: any) => s.id));
            }
        }

        if (log) {
            const parsedLogs = JSON.parse(log);
            const prunedLogs = pruneOldLogs(parsedLogs); 
            setLogs(prunedLogs);
        }

        if (thm) setIsDarkMode(JSON.parse(thm));
        if (gol) setGoals(JSON.parse(gol));
        if (act) setActiveGoalId(act);
        if (savedCats) setCategories(JSON.parse(savedCats));

        if (loadedSubjects.length > 0) checkDailyBadges(loadedSubjects);

      } catch (e) { console.log(e); } finally { setIsLoading(false); }
    })();
  }, []);

  useEffect(() => {
    if (!isLoading) {
        AsyncStorage.setItem('@study_data', JSON.stringify(subjects));
        AsyncStorage.setItem('@study_logs', JSON.stringify(logs));
        AsyncStorage.setItem('@is_dark_mode', JSON.stringify(isDarkMode));
        AsyncStorage.setItem('@user_goals', JSON.stringify(goals));
        AsyncStorage.setItem('@active_goal_id', activeGoalId);
        AsyncStorage.setItem('@home_filter_ids', JSON.stringify(homeFilterIds)); 
        AsyncStorage.setItem('@user_categories', JSON.stringify(categories));
    }
  }, [subjects, logs, goals, activeGoalId, isDarkMode, isLoading, homeFilterIds, categories]); 

  const isAnyTimerRunning = subjects.some(s => s.chapters.some(c => c.isRunning));
  
  const getDailyTotal = () => {
    const todayKey = getTodayKey();
    let total = logs[todayKey] || 0;
    subjects.forEach(sub => {
        sub.chapters.forEach(ch => {
            if (ch.isRunning && ch.lastStartTime) {
                total += (Date.now() - ch.lastStartTime);
            }
        });
    });
    return total;
  };

  const toggleTheme = () => setIsDarkMode(prev => !prev);
  const setActiveGoal = (id: string) => setActiveGoalId(id);
  const addGoal = (l: string, h: number) => { const n = {id:Date.now().toString(),label:l,hours:h}; setGoals(p=>[...p,n]); setActiveGoalId(n.id); };
  const updateGoal = (id:string,l:string,h:number) => setGoals(p=>p.map(g=>g.id===id?{...g,label:l,hours:h}:g));
  const deleteGoal = (id:string) => { const n=goals.filter(g=>g.id!==id); setGoals(n); if(activeGoalId===id&&n.length>0) setActiveGoalId(n[0].id); };
  
  const addSubject = (name:string, target:number) => {
      const newId = Date.now();
      const newSubject = { id: newId, name, hours: 0, target, progress: 0, badges: { gold: 0, silver: 0, bronze: 0 }, chapters: [], note: '', category: '' };
      setSubjects(p => [...p, newSubject]);
      setHomeFilterIds(prev => [...prev, newId]);
  };
  
  const updateSubject = (id:number,f:keyof Subject,v:string|number) => setSubjects(p=>p.map(s=>s.id===id?{...s,[f]:v,progress:f==='target'||f==='hours'?s.hours/Number(v):s.progress}:s));
  
  const deleteSubject = (id:number) => {
      setSubjects(p => p.filter(s => s.id !== id));
      setHomeFilterIds(prev => prev.filter(fid => fid !== id));
  };
  
  const addChapter = (sId:number, cName:string) => setSubjects(p=>p.map(s=>s.id===sId?{...s,chapters:[...s.chapters,{id:Date.now().toString(),name:cName,timeSpent:0,dailyHistory:{},isRunning:false,lastStartTime:null, isHidden: false}]}:s));
  const updateChapterName = (sId:number,cId:string,n:string) => setSubjects(p=>p.map(s=>s.id===sId?{...s,chapters:s.chapters.map(c=>c.id===cId?{...c,name:n}:c)}:s));
  const deleteChapter = (sId:number,cId:string) => setSubjects(p=>p.map(s=>s.id===sId?{...s,chapters:s.chapters.filter(c=>c.id!==cId)}:s));

  const toggleChapterTimer = (subjectId: number, chapterId: string) => {
    const now = Date.now();
    const todayKey = getTodayKey(); 
    let logUpdate = 0;

    setSubjects(prevSubjects => {
        const updatedSubjects = prevSubjects.map(sub => {
            let chaptersChanged = false;
            const newChapters = sub.chapters.map(ch => {
                if ((sub.id === subjectId && ch.id === chapterId && ch.isRunning) || (ch.isRunning && (sub.id !== subjectId || ch.id !== chapterId))) {
                    chaptersChanged = true;
                    const elapsed = now - (ch.lastStartTime || now);
                    logUpdate += elapsed;
                    const newTotal = ch.timeSpent + elapsed;
                    const currentDaily = (ch.dailyHistory && ch.dailyHistory[todayKey]) ? ch.dailyHistory[todayKey] : 0;
                    const newDailyHistory = { ...(ch.dailyHistory || {}), [todayKey]: currentDaily + elapsed };
                    return { ...ch, isRunning: false, timeSpent: newTotal, dailyHistory: newDailyHistory, lastStartTime: null };
                }
                if (sub.id === subjectId && ch.id === chapterId && !ch.isRunning) {
                    chaptersChanged = true;
                    return { ...ch, isRunning: true, lastStartTime: now };
                }
                return ch;
            });
            if (chaptersChanged) {
                const totalMs = newChapters.reduce((sum, c) => sum + c.timeSpent, 0);
                const newTotalHours = parseFloat((totalMs / 3600000).toFixed(2));
                return { ...sub, chapters: newChapters, hours: newTotalHours, progress: newTotalHours / sub.target };
            }
            return sub;
        });
        if (logUpdate > 0) {
            setLogs(prevLogs => ({ ...prevLogs, [todayKey]: (prevLogs[todayKey] || 0) + logUpdate }));
        }
        return updatedSubjects;
    });
  };

  return (
    <StudyContext.Provider value={{ 
      subjects, logs, goals, activeGoalId, theme, isDarkMode, isLoading, isAnyTimerRunning,
      homeFilterIds, categories, 
      setActiveGoalId, addGoal, updateGoal, deleteGoal, toggleTheme,
      addSubject, updateSubject, deleteSubject, addChapter, updateChapterName, deleteChapter, toggleChapterTimer,
      toggleHomeFilter, moveSubject, updateSubjectNote, toggleChapterHidden, updateSubjectCategory, addNewCategory, 
      deleteCategory, editCategory, 
      exportData, importData, 
      getTodayKey, getDailyTotal
    }}>
      {children}
    </StudyContext.Provider>
  );
}

export const useStudy = () => {
  const context = useContext(StudyContext);
  if (!context) throw new Error("useStudy must be used within StudyProvider");
  return context;
};