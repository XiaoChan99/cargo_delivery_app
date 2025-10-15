import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
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
import 'courier_registration.dart';
  

void main() {
  runApp(const CargoDeliveryApp());
}

class CargoDeliveryApp extends StatefulWidget {
  const CargoDeliveryApp({super.key});

  @override
  State<CargoDeliveryApp> createState() => _CargoDeliveryAppState();
}

class _CargoDeliveryAppState extends State<CargoDeliveryApp> {
  final Future<FirebaseApp> _initialization = Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initialization,
      builder: (context, snapshot) {
        // Check for errors
        if (snapshot.hasError) {
          print("Firebase initialization error: ${snapshot.error}");
          return const MaterialApp(
            home: ErrorApp(),
          );
        }

        // Once complete, show your application
        if (snapshot.connectionState == ConnectionState.done) {
          return const MainApp();
        }

        // Otherwise, show a simple loading indicator while waiting for initialization
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('Initializing...'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

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
      // Start directly with the landing page
      home: const LandingPage(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/registration': (context) => const RegistrationPage(),
        '/home': (context) => const HomePage(),
        '/schedule': (context) => const SchedulePage(),
        '/livemap': (context) => const LiveMapPage(),
        '/settings': (context) => const SettingsPage(),
        '/live_location': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return LiveLocationPage(
            cargoData: args['cargoData'],
          );
        },
        '/container_details': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return ContainerDetailsPage(
            containerData: args['containerData'] ?? args['cargoData'], // Support both old and new parameter names
            isAvailable: args['isAvailable'] ?? true, // Default to true if not provided
          );
        },
        '/status_update': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return StatusUpdatePage(
            cargoData: args['cargoData'],
          );
        },
        '/analytics': (context) {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            return AnalyticsPage(userId: user.uid);
          } else {
            // Fallback to login page if user is not authenticated
            return const LoginPage();
          }
        },
        '/info': (context) => const InfoPage(),
        '/change_password': (context) => const ChangePasswordPage(),
        '/terms_privacy': (context) => const TermsPrivacyPage(),
        '/contact_support': (context) => const ContactSupportPage(),
        '/courier-registration': (context) => const CourierRegistrationPage(),
      },
    );
  }
}

class ErrorApp extends StatelessWidget {
  const ErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 20),
              const Text(
                'App Configuration Error',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'There was an issue initializing the app.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              const Text(
                'Please restart the app or check your connection.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                  main();
                },
                child: const Text('Restart App'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}