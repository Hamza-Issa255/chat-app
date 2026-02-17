import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Kazi ya kuingia (Login)
  Future signIn() async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Kuna kosa: ${e.toString()}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_open_rounded, size: 80, color: Colors.blue),
                const SizedBox(height: 25),
                const Text("Welcome again!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                const Text("Login to chat with friends", style: TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 30),

                // Email Input
                _myTextField(_emailController, "Email", false, Icons.email),
                const SizedBox(height: 10),

                // Password Input
                _myTextField(_passwordController, "Password", true, Icons.lock),
                const SizedBox(height: 25),

                // Button ya Login
                GestureDetector(
                  onTap: signIn,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text("Login", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
                  ),
                ),

                const SizedBox(height: 25),
                // Link ya kwenda Register
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("you dont have Account? "),
                    GestureDetector(
                      onTap: () {
                        // Hapa tutaweka logic ya kubadili kwenda Register
                        Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context)=> const RegisterPage(),
                        ),
                        );
                      },
                      child: const Text("Register Now", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _myTextField(TextEditingController controller, String hintText, bool obscure, IconData icon) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.blue),
        enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white), borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.blue), borderRadius: BorderRadius.circular(12)),
        fillColor: Colors.white,
        filled: true,
        hintText: hintText,
      ),
    );
  }
}