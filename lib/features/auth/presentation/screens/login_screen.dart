import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/helpers.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/custom_button.dart';
import '../../../../core/widgets/custom_text_field.dart';
import '../controllers/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  // ─────────────────────────────────────────────────────────────────
  // TEST-ONLY quick login. Flip this to false (or delete the block in
  // build + these constants) before shipping to production.
  static const bool _showTestLogins = true;

  // [name, title, email, password] — leadership on the left, team on the right.
  static const List<List<String>> _managers = [
    ['Ahmed Azzab', 'Owner · CEO', 'ceo@arena.com', '123456'],
    ['Mohamed Shuaib', 'Account Manager', 'shuaib@arena.com', 'Arena@123'],
    ['Khadija', 'Account Manager', 'khadija@arena.com', 'Arena@123'],
    ['Sherouk Diab', 'Account Manager', 'sherouk@arena.com', 'Arena@123'],
    ['Samar Mohamed', 'Creative Director', 'samar@arena.com', 'Arena@123'],
    ['Ahmed Gamal', 'Growth Hacker', 'gamal@arena.com', 'Arena@123'],
    ['Marwan', 'Business Developer', 'marwan@arena.com', 'Arena@123'],
    ['Hend Mostafa', 'Content Creator', 'hend@arena.com', 'Arena@123'],
    ['Zeinab Mahmoud', 'Moderation Lead', 'zeinab@arena.com', 'Arena@123'],
    ['Mariam Salah', 'Backend Developer', 'mariam.salah@arena.com', 'Arena@123'],
    ['Salah El Shamy', 'E-Commerce Manager', 'salah@arena.com', 'Arena@123'],
    ['Hossam Soltan', 'Assistant CEO', 'hossam@arena.com', 'Arena@123'],
  ];
  static const List<List<String>> _team = [
    ['Mustafa Gamal', 'Media Buyer', 'mustafa@arena.com', 'Arena@123'],
    ['Rawan Ramadan', 'Art Director', 'rowan@arena.com', 'Arena@123'],
    ['Mohamed Atef Mohamed', 'Graphic Designer', 'mohamed@arena.com', 'Arena@123'],
    ['Mido', 'Reel Creator', 'mido@arena.com', 'Arena@123'],
    ['Hager', 'Reel Creator', 'hager@arena.com', 'Arena@123'],
    ['Bakinam', 'Media Buyer', 'bakinam@arena.com', 'Arena@123'],
    ['Sara Tarek', 'Moderator', 'sara@arena.com', 'Arena@123'],
    ['Rawan Alaa', 'Moderator', 'rawan@arena.com', 'Arena@123'],
    ['Abdel Rahman Ahmed', 'Graphic Designer', 'body@arena.com', 'Arena@123'],
    ['Helana Wagdy', 'Moderator', 'helana@arena.com', 'Arena@123'],
    ['Karem', 'Videographer', 'karem@arena.com', 'Arena@123'],
    ['Mohamed Halim', 'Backend Developer', 'halim@arena.com', 'Arena@123'],
    ['Mohamed Wageh', 'Photographer', 'wageh@arena.com', 'Arena@123'],
    ['Tasneem Mohamed', 'Social Media', 'tasneem@arena.com', 'Arena@123'],
    ['Ahmed Sayed Ahmed', 'Video Editor', 'sayed@arena.com', 'Arena@123'],
    ['Mariam', 'Photographer & Editor', 'mariam@arena.com', 'Arena@123'],
    ['Bejad Saeed', 'Frontend Developer', 'bejad@arena.com', 'Arena@123'],
    ['Ahmed Yehia', 'Stock Specialist', 'yehia@arena.com', 'Arena@123'],
    ['Rana Mohamed', 'Moderator', 'rana@arena.com', 'Arena@123'],
    ['Mohamed Saeed', 'Stock Specialist', 'moksha@arena.com', 'Arena@123'],
    ['Omar', 'Stock Control', 'omar@arena.com', 'Arena@123'],
    ['Mohamed Mo2a', 'Stock Specialist', 'mo2a@arena.com', 'Arena@123'],
    ['Shehab', 'Frontend Developer', 'shehab@arena.com', 'Arena@123'],
    ['Hoda Tarek', 'Moderator', 'hoda@arena.com', 'Arena@123'],
    ['Nour Hossam', 'Reel Creator', 'nour@arena.com', 'Arena@123'],
    ['Mervat', 'Social Media', 'mervat@arena.com', 'Arena@123'],
    ['Manar', 'Social Media', 'manar@arena.com', 'Arena@123'],
  ];
  // ─────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref.read(authControllerProvider.notifier).login(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
    if (!mounted) return;
    if (!ok) {
      final err = ref.read(authControllerProvider).error;
      final msg = switch (err) {
        ApiException(:final message) => message,
        _ => 'Login failed',
      };
      Helpers.showSnack(context, msg, error: true);
    }
    // On success, AppRouter redirects to /home automatically.
  }

  /// TEST helper: fill the form with a preset account and sign in.
  Future<void> _quickLogin(String email, String password) async {
    _emailCtrl.text = email;
    _passwordCtrl.text = password;
    setState(() {}); // reflect the filled fields in the inputs
    await _submit();
  }

  Widget _testLoginPanel(bool loading) {
    Widget column(String header, Color color, List<List<String>> people) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(header,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: color,),),
            ),
            const SizedBox(height: 8),
            for (final p in people)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: loading ? null : () => _quickLogin(p[2], p[3]),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p[0],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700,),),
                          const SizedBox(height: 1),
                          Text(p[1],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF6B7280),),),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(children: [
          Expanded(child: Divider()),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('TEST LOGIN — remove before live',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF9CA3AF),
                    letterSpacing: 0.5,),),
          ),
          Expanded(child: Divider()),
        ],),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            column('المديرين', const Color(0xFF7C3AED), _managers),
            const SizedBox(width: 10),
            column('الموظفين', const Color(0xFF0891B2), _team),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final loading = auth.isLoading;

    // Dark input styling so the fields read cleanly on the all-black screen.
    final darkForm = Theme.of(context).copyWith(
      textTheme: Theme.of(context)
          .textTheme
          .apply(bodyColor: Colors.white, displayColor: Colors.white),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF161616),
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIconColor: Colors.white54,
        suffixIconColor: Colors.white54,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.arenaBlue, width: 1.5),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),
                // Arena master logo — sits directly on the black canvas.
                Center(
                  child: Image.asset(
                    'assets/images/Logo.png',
                    width: 190,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.chat_bubble_outline,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                Theme(
                  data: darkForm,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CustomTextField(
                        label: 'Email',
                        hint: 'name@arena.com',
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: Icons.email_outlined,
                        validator: Validators.email,
                      ),
                      const SizedBox(height: 16),
                      CustomTextField(
                        label: 'Password',
                        hint: '••••••••',
                        controller: _passwordCtrl,
                        obscureText: true,
                        prefixIcon: Icons.lock_outline,
                        validator: (v) => Validators.password(v, min: 4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                CustomButton(
                  label: 'Sign in',
                  loading: loading,
                  onPressed: _submit,
                ),
                if (_showTestLogins) ...[
                  const SizedBox(height: 28),
                  _testLoginPanel(loading),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
