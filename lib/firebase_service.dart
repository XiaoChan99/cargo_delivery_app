import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseService {
  static bool _initialized = false;
  
  static Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "YOUR_API_KEY",
          appId: "1:497593435460:android:eec4c28e83a95d25850311",
          messagingSenderId: "YOUR_SENDER_ID",
          projectId: "gothong-congestion-management",
          // Add these for web if needed:
          // authDomain: "your-project.firebaseapp.com",
          // storageBucket: "your-project.appspot.com",
        ),
      );
      _initialized = true;
      print("Firebase initialized successfully");
    } catch (e) {
      print("Firebase initialization error: $e");
      throw Exception("Failed to initialize Firebase: $e");
    }
  }
  
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;
  static FirebaseAuth get auth => FirebaseAuth.instance;

  // Collection References
  static CollectionReference get cargos => firestore.collection('cargos');
  static CollectionReference get cargoDeliveries => firestore.collection('cargo_deliveries');
  static CollectionReference get users => firestore.collection('users');
  static CollectionReference get admins => firestore.collection('admins');

  // ========== CARGO OPERATIONS ========== //

  // Add new cargo
  static Future<String> addCargo({
    required String submanifestId,
    required int itemNumber,
    required String description,
    required int quantity,
    required double value,
    required double weight,
    String? additionalInfo,
    String? hsCode,
  }) async {
    try {
      await initialize(); // Ensure Firebase is initialized
      
      // Generate cargo ID
      final cargoId = _generateCargoId();
      
      final docRef = await cargos.add({
        'cargo_id': cargoId,
        'submanifest_id': submanifestId,
        'item_number': itemNumber,
        'description': description,
        'quantity': quantity,
        'value': value,
        'weight': weight,
        'additional_info': additionalInfo,
        'hs_code': hsCode,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      return docRef.id;
    } catch (e) {
      throw Exception('Failed to add cargo: $e');
    }
  }

  // Get all cargos
  static Stream<QuerySnapshot> getAllCargos() {
    return cargos.orderBy('created_at', descending: true).snapshots();
  }

  // Get cargos by submanifest
  static Stream<QuerySnapshot> getCargosBySubmanifest(String submanifestId) {
    return cargos
        .where('submanifest_id', isEqualTo: submanifestId)
        .orderBy('item_number')
        .snapshots();
  }

  // Update cargo
  static Future<void> updateCargo(String docId, Map<String, dynamic> updates) async {
    try {
      await initialize();
      await cargos.doc(docId).update({
        ...updates,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update cargo: $e');
    }
  }

  // Delete cargo
  static Future<void> deleteCargo(String docId) async {
    try {
      await initialize();
      await cargos.doc(docId).delete();
    } catch (e) {
      throw Exception('Failed to delete cargo: $e');
    }
  }

  // ========== CARGO DELIVERY OPERATIONS ========== //

  // Create cargo delivery record
  static Future<String> createCargoDelivery({
    required String cargoId,
    required String confirmedBy,
    String? remarks,
  }) async {
    try {
      await initialize();
      
      final docRef = await cargoDeliveries.add({
        'cargo_id': cargoId,
        'confirmed_by': confirmedBy,
        'confirmed_at': FieldValue.serverTimestamp(),
        'remarks': remarks,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'status': 'delivered',
      });

      // Update cargo status to delivered
      await _updateCargoStatus(cargoId, 'delivered');

      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create delivery record: $e');
    }
  }

  // Get delivery history for a cargo
  static Stream<QuerySnapshot> getCargoDeliveryHistory(String cargoId) {
    return cargoDeliveries
        .where('cargo_id', isEqualTo: cargoId)
        .orderBy('confirmed_at', descending: true)
        .snapshots();
  }

  // Get all deliveries
  static Stream<QuerySnapshot> getAllDeliveries() {
    return cargoDeliveries.orderBy('confirmed_at', descending: true).snapshots();
  }

  // ========== USER OPERATIONS ========== //

  // Get current user ID
  static String? getCurrentUserId() {
    return auth.currentUser?.uid;
  }

  // Get user data
  static Future<DocumentSnapshot> getUserData(String userId) async {
    await initialize();
    return await users.doc(userId).get();
  }

  // Sign in user
  static Future<UserCredential> signInWithEmailAndPassword(String email, String password) async {
    await initialize();
    return await auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // Sign out user
  static Future<void> signOut() async {
    await auth.signOut();
  }

  // Check if user is logged in
  static bool isUserLoggedIn() {
    return auth.currentUser != null;
  }

  // ========== HELPER METHODS ========== //

  // Generate cargo ID (custom logic)
  static String _generateCargoId() {
    final now = DateTime.now();
    return 'C${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${_getRandomNumbers(4)}';
  }

  static String _getRandomNumbers(int length) {
    final random = DateTime.now().millisecond;
    return random.toString().padLeft(length, '0').substring(0, length);
  }

  // Update cargo status
  static Future<void> _updateCargoStatus(String cargoId, String status) async {
    final query = await cargos.where('cargo_id', isEqualTo: cargoId).get();
    if (query.docs.isNotEmpty) {
      await cargos.doc(query.docs.first.id).update({
        'status': status,
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
  }

  // Get cargo by cargo_id (not document ID)
  static Future<DocumentSnapshot?> getCargoByCargoId(String cargoId) async {
    await initialize();
    final query = await cargos.where('cargo_id', isEqualTo: cargoId).get();
    return query.docs.isNotEmpty ? query.docs.first : null;
  }

  // Get cargo by document ID
  static Future<DocumentSnapshot> getCargoById(String docId) async {
    await initialize();
    return await cargos.doc(docId).get();
  }

  // Get delivery by document ID
  static Future<DocumentSnapshot> getDeliveryById(String docId) async {
    await initialize();
    return await cargoDeliveries.doc(docId).get();
  }

  // Check if user is admin
  static Future<bool> isUserAdmin(String userId) async {
    await initialize();
    final doc = await admins.doc(userId).get();
    return doc.exists;
  }

  // Get current user role
  static Future<String> getCurrentUserRole() async {
    final userId = getCurrentUserId();
    if (userId == null) return 'guest';
    
    final isAdmin = await isUserAdmin(userId);
    return isAdmin ? 'admin' : 'user';
  }
}