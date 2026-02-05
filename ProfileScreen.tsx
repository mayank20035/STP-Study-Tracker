import React, { useState, useEffect } from 'react';
import { 
  View, Text, StyleSheet, TouchableOpacity, Alert, ScrollView, Switch, TextInput, Image, Linking 
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as ImagePicker from 'expo-image-picker';
import { useStudy } from './StudyContext';

const TAG_OPTIONS = [ 
  "Night Owl 🦉", "Early Bird ☀️", "Visual Learner 👁️", 
  "Note Taker 📝", "Procrastinator 😅", "Consistent 🏃", 
  "Crammer 📚", "Techie 💻", "Coffee Lover ☕" 
];

export default function ProfileScreen() {
  // Added exportData and importData to destructuring
  const { theme, isDarkMode, toggleTheme, goals, activeGoalId, subjects, exportData, importData } = useStudy();

  // --- STATE ---
  const [name, setName] = useState("Student");
  const [profileImage, setProfileImage] = useState<string | null>(null);
  const [selectedTags, setSelectedTags] = useState<string[]>([]);
  const [isEditingTags, setIsEditingTags] = useState(false); 

  // --- CALCULATIONS ---
  const activeGoal = goals.find(g => g.id === activeGoalId);
  const roleLabel = activeGoal ? activeGoal.label : "Newbie";
  const totalHours = subjects.reduce((acc, sub) => acc + sub.hours, 0);

  // --- LOAD DATA ---
  useEffect(() => {
    (async () => {
      try {
        const [savedName, savedImage, savedTags] = await Promise.all([
            AsyncStorage.getItem('@user_name'),
            AsyncStorage.getItem('@user_image'),
            AsyncStorage.getItem('@user_tags')
        ]);

        if (savedName) setName(savedName);
        if (savedImage) setProfileImage(savedImage);
        if (savedTags) setSelectedTags(JSON.parse(savedTags));
      } catch(e) { console.log("Failed to load profile"); }
    })();
  }, []);

  // --- ACTIONS ---
  const saveName = async (text: string) => { setName(text); await AsyncStorage.setItem('@user_name', text); };
  
  const saveTags = async (newTags: string[]) => { 
    setSelectedTags(newTags); 
    await AsyncStorage.setItem('@user_tags', JSON.stringify(newTags)); 
  };
  
  const toggleTag = (tag: string) => { 
    if (selectedTags.includes(tag)) saveTags(selectedTags.filter(t => t !== tag)); 
    else saveTags([...selectedTags, tag]); 
  };

  const pickImage = async () => {
    let result = await ImagePicker.launchImageLibraryAsync({ 
      mediaTypes: ImagePicker.MediaTypeOptions.Images, allowsEditing: true, aspect: [1, 1], quality: 1 
    });
    if (!result.canceled) { 
      setProfileImage(result.assets[0].uri); 
      await AsyncStorage.setItem('@user_image', result.assets[0].uri); 
    }
  };

  const handleContactSupport = () => {
    Linking.openURL('mailto:support@stp.app');
  };

  const handleReset = async () => { 
    Alert.alert("Reset App Data", "This will delete ALL subjects and history. Are you sure?", [
        { text: "Cancel", style: "cancel" }, 
        { text: "Delete Everything", style: "destructive", onPress: async () => { 
            await AsyncStorage.clear(); 
            Alert.alert("Success", "Please restart the app to apply changes."); 
        }}
    ]); 
  };

  return (
    <ScrollView 
        style={[styles.container, { backgroundColor: theme.background }]} 
        contentContainerStyle={{ paddingBottom: 120 }}
    >
      {/* PROFILE CARD */}
      <View style={[styles.profileCard, { backgroundColor: theme.card }]}>
        <TouchableOpacity onPress={pickImage} style={styles.avatarWrapper}>
            {profileImage ? (
                <Image source={{ uri: profileImage }} style={styles.avatarImage} />
            ) : (
                <View style={[styles.avatarContainer, { backgroundColor: theme.primary }]}>
                    <Ionicons name="person" size={40} color="#fff" />
                </View>
            )}
            <View style={[styles.editIconBadge, { backgroundColor: theme.card }]}>
                <Ionicons name="camera" size={14} color={theme.text} />
            </View>
        </TouchableOpacity>
        
        <TextInput 
            style={[styles.nameInput, { color: theme.text, borderBottomColor: theme.border }]} 
            value={name} onChangeText={saveName} placeholder="Enter Name" placeholderTextColor={theme.textLight} 
        />
        
        <Text style={[styles.roleText, { color: theme.primary, fontWeight: 'bold', marginTop: 5 }]}>
            {roleLabel}
        </Text> 

        {/* STATS ROW */}
        <View style={[styles.statsRow, { borderTopColor: theme.border }]}>
            <View style={styles.statItem}>
                <Text style={[styles.statValue, { color: theme.text }]}>{subjects.length}</Text>
                <Text style={[styles.statLabel, { color: theme.textLight }]}>Subjects</Text>
            </View>
            <View style={[styles.statDivider, { backgroundColor: theme.border }]} />
            <View style={styles.statItem}>
                <Text style={[styles.statValue, { color: theme.text }]}>{totalHours.toFixed(1)}</Text>
                <Text style={[styles.statLabel, { color: theme.textLight }]}>Total Hours</Text>
            </View>
        </View>
      </View>

      {/* --- TRAITS SECTION --- */}
      <View style={styles.section}>
        <View style={{flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 15}}>
             <Text style={[styles.sectionTitle, { color: theme.text, marginBottom: 0 }]}>My Traits</Text>
             <TouchableOpacity onPress={() => setIsEditingTags(!isEditingTags)}>
                 <Text style={{color: theme.primary, fontWeight: 'bold'}}>
                    {isEditingTags ? "Done" : "Edit"}
                 </Text>
             </TouchableOpacity>
        </View>
        
        <View style={{flexDirection: 'row', flexWrap: 'wrap'}}>
            {isEditingTags ? (
                TAG_OPTIONS.map((tag) => {
                    const isSelected = selectedTags.includes(tag);
                    return (
                        <TouchableOpacity key={tag} onPress={() => toggleTag(tag)} style={[styles.tagBadge, { backgroundColor: isSelected ? theme.primary : theme.card, borderColor: theme.border, borderWidth: isSelected ? 0 : 1 }]}>
                            <Text style={[styles.tagText, { color: isSelected ? '#fff' : theme.text }]}>{tag}</Text>
                        </TouchableOpacity>
                    );
                })
            ) : (
                selectedTags.length > 0 ? (
                    selectedTags.map((tag) => (
                        <View key={tag} style={[styles.tagBadge, { backgroundColor: theme.primary, borderColor: theme.border, borderWidth: 0 }]}>
                            <Text style={[styles.tagText, { color: '#fff' }]}>{tag}</Text>
                        </View>
                    ))
                ) : (
                    <Text style={{color: theme.textLight, fontStyle: 'italic'}}>No traits selected. Tap Edit.</Text>
                )
            )}
        </View>
      </View>

      {/* SETTINGS */}
      <View style={styles.section}>
        <Text style={[styles.sectionTitle, { color: theme.text }]}>Settings</Text>
        
        {/* Dark Mode */}
        <View style={[styles.settingRow, { backgroundColor: theme.card }]}>
            <View style={{flexDirection:'row', alignItems:'center'}}>
                <View style={[styles.iconBox, { backgroundColor: theme.secondary }]}>
                    <Ionicons name="moon" size={20} color={theme.primary} />
                </View>
                <Text style={[styles.settingText, { color: theme.text }]}>Dark Mode</Text>
            </View>
            <Switch value={isDarkMode} onValueChange={toggleTheme} trackColor={{ false: '#D1D5DB', true: theme.primary }} thumbColor={'#fff'} />
        </View>

        {/* Support */}
        <TouchableOpacity style={[styles.settingRow, { backgroundColor: theme.card }]} onPress={handleContactSupport}>
            <View style={{flexDirection:'row', alignItems:'center'}}>
                <View style={[styles.iconBox, { backgroundColor: '#DCFCE7' }]}>
                    <Ionicons name="mail" size={20} color="#16A34A" />
                </View>
                <Text style={[styles.settingText, { color: theme.text }]}>Contact Support</Text>
            </View>
            <Ionicons name="chevron-forward" size={20} color={theme.textLight} />
        </TouchableOpacity>

        {/* Reset */}
        <TouchableOpacity style={[styles.settingRow, { backgroundColor: theme.card, marginTop: 10 }]} onPress={handleReset}>
            <View style={{flexDirection:'row', alignItems:'center'}}>
                <View style={[styles.iconBox, { backgroundColor: '#FEE2E2' }]}>
                    <Ionicons name="trash-bin" size={20} color="#EF4444" />
                </View>
                <Text style={[styles.settingText, { color: '#EF4444' }]}>Reset All Data</Text>
            </View>
        </TouchableOpacity>
      </View>

      {/* DATA & STORAGE (NEW SECTION) */}
      <View style={styles.section}>
        <Text style={[styles.sectionTitle, { color: theme.text }]}>Data & Backup</Text>

        {/* Export Data */}
        <TouchableOpacity style={[styles.settingRow, { backgroundColor: theme.card }]} onPress={exportData}>
            <View style={{flexDirection:'row', alignItems:'center'}}>
                <View style={[styles.iconBox, { backgroundColor: '#DBEAFE' }]}>
                    <Ionicons name="cloud-upload" size={20} color="#3B82F6" />
                </View>
                <Text style={[styles.settingText, { color: theme.text }]}>Export Backup</Text>
            </View>
            <Ionicons name="chevron-forward" size={20} color={theme.textLight} />
        </TouchableOpacity>

        {/* Import Data */}
        <TouchableOpacity style={[styles.settingRow, { backgroundColor: theme.card }]} onPress={importData}>
            <View style={{flexDirection:'row', alignItems:'center'}}>
                <View style={[styles.iconBox, { backgroundColor: '#FEF3C7' }]}>
                    <Ionicons name="cloud-download" size={20} color="#D97706" />
                </View>
                <Text style={[styles.settingText, { color: theme.text }]}>Import Backup</Text>
            </View>
            <Ionicons name="chevron-forward" size={20} color={theme.textLight} />
        </TouchableOpacity>
      </View>
      
      <Text style={[styles.versionText, { color: theme.textLight }]}>STP v1.1.0</Text>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, paddingTop: 60, paddingHorizontal: 20 },
  profileCard: { padding: 20, borderRadius: 16, alignItems: 'center', marginBottom: 20, elevation: 2 },
  avatarWrapper: { position: 'relative', marginBottom: 15 },
  avatarContainer: { width: 100, height: 100, borderRadius: 50, justifyContent: 'center', alignItems: 'center' },
  avatarImage: { width: 100, height: 100, borderRadius: 50 },
  editIconBadge: { position: 'absolute', bottom: 0, right: 0, padding: 6, borderRadius: 15, elevation: 2 },
  nameInput: { fontSize: 22, fontWeight: 'bold', textAlign: 'center', borderBottomWidth: 1, minWidth: 150, paddingBottom: 5, marginBottom: 5 },
  roleText: { fontSize: 16, letterSpacing: 1 },
  statsRow: { flexDirection: 'row', width: '100%', justifyContent: 'space-around', borderTopWidth: 1, paddingTop: 15, marginTop: 20 },
  statItem: { alignItems: 'center' },
  statValue: { fontSize: 20, fontWeight: 'bold' },
  statLabel: { fontSize: 12 },
  statDivider: { width: 1, height: '80%' },
  section: { marginTop: 15 },
  sectionTitle: { fontSize: 14, fontWeight: 'bold', marginBottom: 10, letterSpacing: 1, opacity: 0.8 },
  tagBadge: { paddingVertical: 8, paddingHorizontal: 16, borderRadius: 20, marginRight: 8, marginBottom: 8 },
  tagText: { fontSize: 14, fontWeight: '600' },
  settingRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', padding: 16, borderRadius: 12, marginBottom: 10, elevation: 1 },
  settingText: { fontSize: 16, fontWeight: '500', marginLeft: 15 },
  iconBox: { width: 32, height: 32, borderRadius: 8, justifyContent: 'center', alignItems: 'center' },
  versionText: { textAlign: 'center', marginTop: 30, fontSize: 12, paddingBottom: 20 }
});