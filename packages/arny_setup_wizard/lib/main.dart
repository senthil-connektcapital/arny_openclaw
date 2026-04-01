import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'system_manager.dart';
import 'backend_client.dart';
import 'openclaw_config.dart';
import 'user_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(540, 420),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    maximumSize: Size(540, 420),
    minimumSize: Size(540, 420),
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setResizable(false);
  });

  runApp(const ArnySetupWizardApp());
}

class ArnySetupWizardApp extends StatelessWidget {
  const ArnySetupWizardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Arny Setup Wizard',
      theme: ThemeData(
        fontFamily: '.AppleSystemUIFont', // Native macOS font
        scaffoldBackgroundColor: const Color(0xFFECECEC),
        colorScheme: ColorScheme.fromSeed(seedColor: CupertinoColors.activeBlue),
      ),
      home: const WizardShell(),
    );
  }
}

class WizardShell extends StatefulWidget {
  const WizardShell({super.key});

  @override
  State<WizardShell> createState() => _WizardShellState();
}

class _WizardShellState extends State<WizardShell> {
  int _currentStep = 0;
  bool _isBusy = false;
  String? _error;
  String? _statusMessage;
  
  SystemStatus _status = SystemStatus();
  BrowserStatus? _browserStatus;

  // Inputs
  String _email = "";
  String _password = "";
  String _gatewayPassword = "";
  bool _autoStart = true;
  bool _enableBrowser = false;
  BrowserInfo? _selectedBrowser;
  
  // State
  String? _accessToken;
  String? _userId;
  String _assistantName = "Arny";

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Try to load saved user session first
    final savedSession = await UserPreferences.loadUserSession();
    if (savedSession != null) {
      setState(() {
        _email = savedSession['email'];
        _accessToken = savedSession['accessToken'];
        _userId = savedSession['userId'];
        _assistantName = savedSession['assistantName'];
        _autoStart = savedSession['autoStart'];
        
        // If we have a valid session, skip to step 2 (browser automation)
        _currentStep = 2;
      });
      print("[App] Restored user session for ${savedSession['email']}");
    }
    
    // Always refresh system status
    _refreshSystemStatus();
  }

  Future<void> _refreshSystemStatus() async {
    setState(() { _isBusy = true; _error = null; _statusMessage = "Checking your system..."; });
    try {
      _status = await OpenClawSystem.checkStatus();
      if (_status.allReady) {
        _currentStep = 1; // Auto advance if ready
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      setState(() { _isBusy = false; _statusMessage = null; });
    }
  }

  void _nextStep() {
    if (_currentStep < 4) {
      setState(() { _currentStep++; _error = null; _statusMessage = null; });
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() {
         _currentStep--;
         _error = null;
         _statusMessage = null;
      });
    }
  }

  Future<void> _fixIssues() async {
    setState(() { _isBusy = true; _error = null; _statusMessage = "Starting installation..."; });
    try {
      if (!_status.openclawInstalled) {
        setState(() => _statusMessage = "Installing OpenClaw CLI...");
        await OpenClawSystem.installOpenClaw();
      }
      if (!_status.ollamaInstalled) {
        setState(() => _statusMessage = "Installing Ollama...");
        await OpenClawSystem.installOllama();
      }
      if (!_status.ollamaRunning) {
        setState(() => _statusMessage = "Starting Ollama service...");
        await OpenClawSystem.startOllama();
      }
      if (!_status.modelInstalled) {
        setState(() => _statusMessage = "Downloading AI Model (this may take a few minutes)...");
        await OpenClawSystem.pullModel();
      }
      setState(() => _statusMessage = "Verifying setup...");
      _status = await OpenClawSystem.checkStatus();
      if (_status.allReady) _nextStep();
    } catch (e) {
      _error = e.toString();
    } finally {
      setState(() { _isBusy = false; _statusMessage = null; });
    }
  }

  Future<void> _signIn() async {
    if (_email.isEmpty || _password.isEmpty) return;
    setState(() { _isBusy = true; _error = null; _statusMessage = "Signing in..."; });
    try {
      final creds = await BackendClient.signIn(_email, _password);
      _accessToken = creds['accessToken'];
      _userId = creds['userId'];
      
      setState(() => _statusMessage = "Fetching profile...");
      final profile = await BackendClient.fetchProfile(_accessToken!, _userId!);
      if (profile['displayName']?.isNotEmpty == true) {
        _assistantName = profile['displayName'];
      }
      
      // Save user session (but NOT the password)
      await UserPreferences.saveUserSession(
        email: _email,
        userId: _userId!,
        accessToken: _accessToken!,
        assistantName: _assistantName,
        autoStart: _autoStart,
      );
      
      _nextStep();
    } catch (e) {
      _error = e.toString();
    } finally {
      setState(() { _isBusy = false; _statusMessage = null; });
    }
  }

  Future<void> _connectGateway() async {
    if (_gatewayPassword.isEmpty) return;
    setState(() { _isBusy = true; _error = null; _statusMessage = "Saving configuration..."; });
    try {
      // 1. Hash Password for Gateway Token
      final bytes = utf8.encode(_gatewayPassword);
      final digest = sha256.convert(bytes);
      final gatewayTokenHash = digest.toString();

      // 2. Configure OpenClaw using CLI commands (let OpenClaw handle its own config)
      setState(() => _statusMessage = "Configuring OpenClaw...");
      await OpenClawConfig.configureForArny(
        gatewayToken: gatewayTokenHash,
        backendUrl: BackendClient.defaultBackendUrl,
        assistantName: _assistantName,
      );

      // 3. Start Gateway & Verify it is running
      setState(() => _statusMessage = "Starting local gateway...");
      await OpenClawSystem.startGatewayAndVerify();

      // 4. Heartbeat Backend
      setState(() => _statusMessage = "Linking gateway to Arny...");
      print("[App] Sending heartbeat to backend with token: ${gatewayTokenHash.substring(0, 8)}...");
      await BackendClient.postHeartbeat(
        accessToken: _accessToken!,
        gatewayToken: gatewayTokenHash,
        gatewayUrl: "ws://127.0.0.1:18789",
      );
      print("[App] Heartbeat sent successfully!");

      // 5. Auto Start
      if (_autoStart) {
        setState(() => _statusMessage = "Configuring auto-start...");
        await OpenClawSystem.enableGatewayAutostart();
      }

      _nextStep();
    } catch (e) {
      _error = e.toString();
    } finally {
      setState(() { _isBusy = false; _statusMessage = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Native hidden title bar drag area
          const SizedBox(
            height: 38,
            child: DragToMoveArea(child: SizedBox.expand()),
          ),
          
          // Main Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 50.0, vertical: 20.0),
              child: _buildStepContent(),
            ),
          ),
          
          // Footer
          Container(
            height: 52,
            decoration: const BoxDecoration(
              color: Color(0xFFF5F5F5),
              border: Border(top: BorderSide(color: Color(0xFFD1D1D1), width: 1)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: _buildFooterButtons(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1(); // System Check
      case 1:
        return _buildStep2(); // Sign In
      case 2:
        return _buildStep3(); // Browser Automation
      case 3:
        return _buildStep4(); // Gateway Settings
      case 4:
        return _buildDoneStep(); // Done
      default:
        return const SizedBox.shrink();
    }
  }

  List<Widget> _buildFooterButtons() {
    if (_currentStep == 4) {
      return [
        CupertinoButton.filled(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
          onPressed: () => exit(0),
          child: const Text("Close", style: TextStyle(fontSize: 13)),
        )
      ];
    }

    VoidCallback? primaryAction;
    String primaryLabel = "Continue";

    if (_currentStep == 0) {
      primaryAction = _status.allReady ? _nextStep : _fixIssues;
      primaryLabel = _status.allReady ? "Continue" : "Fix Issues";
    } else if (_currentStep == 1) {
      primaryAction = _email.isNotEmpty && _password.isNotEmpty ? _signIn : null;
    } else if (_currentStep == 2) {
      if (_enableBrowser && _selectedBrowser != null) {
        primaryAction = () async {
          await _configureBrowser();
          _nextStep();
        };
        primaryLabel = "Configure Browser";
      } else {
        primaryAction = _nextStep;
        primaryLabel = "Skip Browser";
      }
    } else if (_currentStep == 3) {
      primaryAction = _gatewayPassword.isNotEmpty ? _connectGateway : null;
      primaryLabel = "Connect";
    }

    return [
      if (_currentStep > 0)
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
          onPressed: _isBusy ? null : _prevStep,
          child: const Text("Back", style: TextStyle(fontSize: 13, color: CupertinoColors.black)),
        ),
      if (_currentStep == 0)
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
          onPressed: _isBusy || _status.allReady ? null : _refreshSystemStatus,
          child: const Text("Refresh", style: TextStyle(fontSize: 13, color: CupertinoColors.black)),
        ),
      if ((_currentStep == 2 || _currentStep == 3) && _accessToken != null)
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
          onPressed: _isBusy ? null : () async {
            await UserPreferences.clearUserSession();
            setState(() {
              _currentStep = 1;
              _accessToken = null;
              _userId = null;
              _email = "";
              _password = "";
            });
          },
          child: const Text("Sign Out", style: TextStyle(fontSize: 13, color: CupertinoColors.black)),
        ),
      const SizedBox(width: 8),
      CupertinoButton.filled(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
        onPressed: _isBusy ? null : primaryAction,
        child: _isBusy 
          ? const CupertinoActivityIndicator(color: Colors.white, radius: 8)
          : Text(primaryLabel, style: const TextStyle(fontSize: 13)),
      )
    ];
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Checking System Requirements", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text("Arny is verifying the assistant engine on this Mac.", style: TextStyle(color: Color(0xFF4A4A4A), fontSize: 13)),
        const SizedBox(height: 24),
        
        // Group Box
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD1D1D1)),
          ),
          child: Column(
            children: [
              _buildGroupRow("Assistant Engine", _status.openclawInstalled ? "Ready" : "Pending", isGood: _status.openclawInstalled),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE5E5E5)),
              _buildGroupRow("Local AI Engine", _status.ollamaRunning ? "Ready" : "Pending", isGood: _status.ollamaRunning),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE5E5E5)),
              _buildGroupRow("Assistant Model", _status.modelInstalled ? "Ready" : "Pending", isGood: _status.modelInstalled),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!, style: const TextStyle(color: CupertinoColors.destructiveRed, fontSize: 13)),
          )
        else if (_isBusy && _statusMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                const CupertinoActivityIndicator(radius: 8),
                const SizedBox(width: 8),
                Expanded(child: Text(_statusMessage!, style: const TextStyle(color: CupertinoColors.activeBlue, fontSize: 13, fontWeight: FontWeight.w500))),
              ],
            ),
          )
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Connect Your Account", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text("Sign in with your Arny account to personalize your assistant.", style: TextStyle(color: Color(0xFF4A4A4A), fontSize: 13)),
        const SizedBox(height: 24),
        
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD1D1D1)),
          ),
          child: Column(
            children: [
              _buildInputRow("Arny Email", "you@example.com", false, _email, (v) => setState(() => _email = v)),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE5E5E5)),
              _buildInputRow("Arny Password", "••••••••", true, _password, (v) => setState(() => _password = v)),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!, style: const TextStyle(color: CupertinoColors.destructiveRed, fontSize: 13)),
          )
        else if (_isBusy && _statusMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                const CupertinoActivityIndicator(radius: 8),
                const SizedBox(width: 8),
                Expanded(child: Text(_statusMessage!, style: const TextStyle(color: CupertinoColors.activeBlue, fontSize: 13, fontWeight: FontWeight.w500))),
              ],
            ),
          )
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Browser Automation", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text("Enable browser automation to let Arny browse the web for you.", style: TextStyle(color: Color(0xFF4A4A4A), fontSize: 13)),
        const SizedBox(height: 24),
        
        // Enable Browser Toggle
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD1D1D1)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Enable Browser Automation", style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                CupertinoSwitch(
                  value: _enableBrowser,
                  activeColor: CupertinoColors.activeGreen,
                  onChanged: (val) async {
                    setState(() => _enableBrowser = val);
                    if (val) {
                      await _checkBrowserStatus();
                    }
                  },
                )
              ],
            ),
          ),
        ),
        
        if (_enableBrowser) ...[
          const SizedBox(height: 16),
          if (_browserStatus != null && _browserStatus!.hasAvailableBrowsers) ...[
            // Browser Selection
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD1D1D1)),
              ),
              child: Column(
                children: _browserStatus!.availableBrowsers
                    .where((browser) => browser.isInstalled)
                    .map((browser) => _buildBrowserRow(browser))
                    .toList(),
              ),
            ),
          ] else if (_browserStatus != null && !_browserStatus!.hasAvailableBrowsers) ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD1D1D1)),
              ),
              padding: const EdgeInsets.all(16),
              child: const Row(
                children: [
                  Icon(CupertinoIcons.exclamationmark_triangle, color: CupertinoColors.systemOrange, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "No supported browsers found. Please install Chrome, Brave, Edge, or Chromium to enable browser automation.",
                      style: TextStyle(fontSize: 13, color: Color(0xFF4A4A4A)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
        
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!, style: const TextStyle(color: CupertinoColors.destructiveRed, fontSize: 13)),
          )
        else if (_isBusy && _statusMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                const CupertinoActivityIndicator(radius: 8),
                const SizedBox(width: 8),
                Expanded(child: Text(_statusMessage!, style: const TextStyle(color: CupertinoColors.activeBlue, fontSize: 13, fontWeight: FontWeight.w500))),
              ],
            ),
          )
      ],
    );
  }

  Widget _buildStep4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Gateway Settings", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text("Set a local connection passphrase and configure auto-start.", style: TextStyle(color: Color(0xFF4A4A4A), fontSize: 13)),
        const SizedBox(height: 24),
        
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD1D1D1)),
          ),
          child: _buildInputRow("Local Passphrase", "Create a strong password", true, _gatewayPassword, (v) => setState(() => _gatewayPassword = v)),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD1D1D1)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Start Arny with my Mac", style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                CupertinoSwitch(
                  value: _autoStart,
                  activeColor: CupertinoColors.activeGreen,
                  onChanged: (val) => setState(() => _autoStart = val),
                )
              ],
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!, style: const TextStyle(color: CupertinoColors.destructiveRed, fontSize: 13)),
          )
        else if (_isBusy && _statusMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                const CupertinoActivityIndicator(radius: 8),
                const SizedBox(width: 8),
                Expanded(child: Text(_statusMessage!, style: const TextStyle(color: CupertinoColors.activeBlue, fontSize: 13, fontWeight: FontWeight.w500))),
              ],
            ),
          )
      ],
    );
  }

  Widget _buildDoneStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(CupertinoIcons.check_mark_circled_solid, color: CupertinoColors.activeGreen, size: 64),
        SizedBox(height: 16),
        Text("Arny is Ready", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        Text("The Arny Gateway is running in the background.\nYou can now safely close this window.", 
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF4A4A4A), fontSize: 13, height: 1.4)
        ),
      ],
    );
  }

  Widget _buildGroupRow(String label, String value, {bool isGood = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          Text(value, style: TextStyle(color: isGood ? CupertinoColors.activeGreen : const Color(0xFF8E8E93), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildInputRow(String label, String placeholder, bool obscure, String value, Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          const SizedBox(height: 4),
          TextField(
            obscureText: obscure,
            style: const TextStyle(fontSize: 13),
            onChanged: onChanged,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: placeholder,
              hintStyle: const TextStyle(color: Color(0xFF9E9E9E)),
              border: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkBrowserStatus() async {
    try {
      setState(() => _isBusy = true);
      _browserStatus = await OpenClawSystem.checkBrowserStatus();
      
      // Auto-select first available browser
      if (_browserStatus!.hasAvailableBrowsers && _selectedBrowser == null) {
        _selectedBrowser = _browserStatus!.availableBrowsers.firstWhere((b) => b.isInstalled);
      }
      
      setState(() {});
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isBusy = false);
    }
  }

  Widget _buildBrowserRow(BrowserInfo browser) {
    final isSelected = _selectedBrowser?.name == browser.name;
    
    return GestureDetector(
      onTap: () {
        setState(() => _selectedBrowser = browser);
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0F8FF) : Colors.white,
          border: isSelected ? Border.all(color: CupertinoColors.activeBlue, width: 2) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _getBrowserIcon(browser.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(browser.name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                  Text(browser.description, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 11)),
                ],
              ),
            ),
            if (isSelected)
              const Icon(CupertinoIcons.check_mark_circled_solid, color: CupertinoColors.activeBlue, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _getBrowserIcon(String browserName) {
    IconData iconData;
    Color iconColor;
    
    switch (browserName.toLowerCase()) {
      case 'brave':
        iconData = CupertinoIcons.shield_fill;
        iconColor = const Color(0xFFFB542B);
        break;
      case 'chrome':
        iconData = CupertinoIcons.globe;
        iconColor = const Color(0xFF4285F4);
        break;
      case 'edge':
        iconData = CupertinoIcons.compass_fill;
        iconColor = const Color(0xFF0078D4);
        break;
      case 'chromium':
        iconData = CupertinoIcons.circle_fill;
        iconColor = const Color(0xFF4A90E2);
        break;
      default:
        iconData = CupertinoIcons.globe;
        iconColor = CupertinoColors.systemGrey;
    }
    
    return Icon(iconData, color: iconColor, size: 24);
  }

  Future<void> _configureBrowser() async {
    if (!_enableBrowser || _selectedBrowser == null) {
      return;
    }
    
    try {
      setState(() {
        _isBusy = true;
        _error = null;
        _statusMessage = "Configuring browser automation...";
      });
      
      await OpenClawSystem.configureBrowser(_selectedBrowser!);
      
      setState(() => _statusMessage = "Verifying gateway is running...");
      // Ensure gateway is running before testing browser
      if (!await OpenClawSystem.isGatewayRunning()) {
        await OpenClawSystem.startGatewayAndVerify();
      }
      
      setState(() => _statusMessage = "Testing browser automation...");
      await OpenClawSystem.testBrowserAutomation();
      
      setState(() => _statusMessage = "Browser automation configured successfully!");
      await Future.delayed(const Duration(seconds: 1));
      
    } catch (e) {
      setState(() {
        _error = "Failed to configure browser: $e";
        _statusMessage = null;
      });
      // Don't advance to next step if there's an error
      return;
    } finally {
      setState(() {
        _isBusy = false;
        _statusMessage = null;
      });
    }
  }
}
