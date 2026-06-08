import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LimitService {
  static const int DAILY_LIMIT = 15;

  static Future<void> syncRemainingToPrefs() async {
    final remaining = await getRemainingQuota();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('remaining_quota', remaining);
    print('LimitService: syncRemainingToPrefs -> remaining_quota = $remaining');
  }

  static Future<int> getRemainingQuota() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data();
    if (data == null) return 0;

    final isPremium = data['isPremium'] ?? false;
    final premiumUntil = data['premiumUntil'] as Timestamp?;
    if (isPremium && premiumUntil != null && premiumUntil.toDate().isAfter(DateTime.now())) {
      return -1;
    }

    final lastDate = data['lastCountDate'] as Timestamp?;
    final today = DateTime.now().toUtc();
    int dailyCount = data['dailyCount'] ?? 0;

    if (lastDate == null || lastDate.toDate().day != today.day) {
      dailyCount = 0;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'dailyCount': 0,
        'lastCountDate': Timestamp.fromDate(today),
      });
    }

    final remaining = DAILY_LIMIT - dailyCount;
    return remaining > 0 ? remaining : 0;
  }

  static Future<bool> checkLimit() async {
    final remaining = await getRemainingQuota();
    if (remaining == -1) return true;
    final ok = remaining > 0;
    await syncRemainingToPrefs();
    return ok;
  }

  static Future<void> incrementCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'dailyCount': FieldValue.increment(1),
    });
    await syncRemainingToPrefs();
    print('LimitService: incrementCount called');
  }
}