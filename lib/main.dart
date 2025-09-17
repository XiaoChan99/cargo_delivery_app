import 'package:flutter/material.dart';
import 'login_page.dart';
import 'registration_page.dart';
import 'homepage.dart';
import 'schedulepage.dart';
import 'livemap_page.dart';
import 'settings_page.dart';
import 'live_location_page.dart';
import 'container_details_page.dart';
import 'status_update_page.dart';
import 'analytics_page.dart';
import 'info_page.dart';
import 'change_password_page.dart';
import 'terms_privacy_page.dart';
import 'contact_support_page.dart';
import 'landing_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'courier_registration.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with error handling
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print("Firebase initialized successfully");
    runApp(const CargoDeliveryApp());
  } catch (e) {
    print("Firebase initialization failed: $e");
    // Fallback: Run app without Firebase
    runApp(const CargoDeliveryAppWithoutFirebase());
  }
}

// Fallback app for when Firebase initialization fails
class CargoDeliveryAppWithoutFirebase extends StatelessWidget {
  const CargoDeliveryAppWithoutFirebase({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Port Congestion Management',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 20),
                const Text(
                  'Firebase Configuration Error',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'The app could not connect to Firebase services.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Please check your internet connection and try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () {
                    // Try to restart the app
                    main();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CargoDeliveryApp extends StatelessWidget {
  const CargoDeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Port Congestion Management',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const LandingPage(),
        '/login': (context) => const LoginPage(),
        '/registration': (context) => const RegistrationPage(),
        '/home': (context) => const HomePage(),
        '/schedule': (context) => const SchedulePage(),
        '/livemap': (context) => const LiveMapPage(),
        '/settings': (context) => const SettingsPage(),
        '/live_location': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, String>;
          return LiveLocationPage(
            containerNo: args['containerNo']!,
            time: args['time']!,
            pickup: args['pickup']!,
            destination: args['destination']!,
            status: args['status']!,
          );
        },
        '/container_details': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, String>;
          return ContainerDetailsPage(
            containerNo: args['containerNo']!,
            time: args['time']!,
            pickup: args['pickup']!,
            destination: args['destination']!,
            status: args['status']!,
          );
        },
        '/status_update': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, String>;
          return StatusUpdatePage(
            containerNo: args['containerNo']!,
            time: args['time']!,
            pickup: args['pickup']!,
            destination: args['destination']!,
            currentStatus: args['currentStatus']!,
          );
        },
        '/analytics': (context) => const AnalyticsPage(),
        '/info': (context) => const InfoPage(),
        '/change_password': (context) => const ChangePasswordPage(),
        '/terms_privacy': (context) => const TermsPrivacyPage(),
        '/contact_support': (context) => const ContactSupportPage(),
        '/courier-registration': (context) => const CourierRegistrationPage(),
      },
    );
  }
}