import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class SystemStatus {
  bool openclawInstalled = false;
  bool ollamaInstalled = false;
  bool ollamaRunning = false;
  bool modelInstalled = false;
  bool get allReady => openclawInstalled && ollamaInstalled && ollamaRunning && modelInstalled;
}

class OpenClawSystem {
  static const String modelName = 'qwen3.5:0.8b';
  
  static Future<String> _getRepoRoot() async {
    final dir = Directory.current;
    if (dir.path.endsWith('arny_setup_wizard')) {
      return dir.parent.parent.path;
    }
    return '/Users/ckc/Documents/github/dev/arny_openclaw';
  }

  static Future<ProcessResult> _runOpenClaw(List<String> args) async {
    final root = await _getRepoRoot();
    final packageJsonPath = '$root/package.json';
    
    // In Flutter macOS, the process environment might not have access to standard user path variables.
    // We inject a standard PATH so commands like 'pnpm', 'node', and 'brew' resolve.
    final env = Map<String, String>.from(Platform.environment);
    env['PATH'] = '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${env['PATH'] ?? ''}';

    if (await File(packageJsonPath).exists()) {
      print("[OpenClawSystem] Running command: pnpm openclaw ${args.join(' ')}");
      return Process.run('pnpm', ['openclaw', ...args], workingDirectory: root, environment: env);
    }
    print("[OpenClawSystem] Fallback to global openclaw: openclaw ${args.join(' ')}");
    return Process.run('openclaw', args, environment: env);
  }

  static Future<Process> _startOpenClaw(List<String> args) async {
    final root = await _getRepoRoot();
    final packageJsonPath = '$root/package.json';
    
    final env = Map<String, String>.from(Platform.environment);
    env['PATH'] = '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${env['PATH'] ?? ''}';

    if (await File(packageJsonPath).exists()) {
      print("[OpenClawSystem] Starting detached process: pnpm openclaw ${args.join(' ')}");
      return Process.start('pnpm', ['openclaw', ...args], workingDirectory: root, environment: env, mode: ProcessStartMode.detached);
    }
    print("[OpenClawSystem] Fallback starting detached process: openclaw ${args.join(' ')}");
    return Process.start('openclaw', args, environment: env, mode: ProcessStartMode.detached);
  }

  // --- CHECKS ---
  
  static Future<SystemStatus> checkStatus() async {
    print("[OpenClawSystem] Checking system status...");
    final status = SystemStatus();
    
    final env = Map<String, String>.from(Platform.environment);
    env['PATH'] = '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${env['PATH'] ?? ''}';

    // Check OpenClaw
    final root = await _getRepoRoot();
    if (await File('$root/package.json').exists()) {
      print("[OpenClawSystem] Local repo openclaw found at $root via pnpm");
      status.openclawInstalled = true;
    } else {
      final ocResult = await Process.run('which', ['openclaw'], environment: env);
      status.openclawInstalled = ocResult.exitCode == 0;
      print("[OpenClawSystem] Global openclaw found: ${status.openclawInstalled}");
    }

    // Check Ollama Installed
    final olResult = await Process.run('which', ['ollama'], environment: env);
    status.ollamaInstalled = olResult.exitCode == 0;
    print("[OpenClawSystem] Ollama installed: ${status.ollamaInstalled}");

    // Check Ollama Running & Model
    if (status.ollamaInstalled) {
      try {
        final response = await http.get(Uri.parse('http://127.0.0.1:11434/api/tags'));
        if (response.statusCode == 200) {
          status.ollamaRunning = true;
          final json = jsonDecode(response.body);
          final models = json['models'] as List<dynamic>? ?? [];
          status.modelInstalled = models.any((m) => m['name'] == modelName);
          print("[OpenClawSystem] Ollama is running. Model installed: ${status.modelInstalled}");
        }
      } catch (_) {
        status.ollamaRunning = false;
        print("[OpenClawSystem] Ollama is NOT running (connection refused).");
      }
    }

    print("[OpenClawSystem] Status check complete. All ready? ${status.allReady}");
    return status;
  }

  // --- INSTALLERS ---

  static Map<String, String> _getEnv() {
    final env = Map<String, String>.from(Platform.environment);
    env['PATH'] = '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${env['PATH'] ?? ''}';
    return env;
  }

  static Future<void> installOpenClaw() async {
    print("[OpenClawSystem] Installing global OpenClaw...");
    final result = await Process.run('npm', ['install', '-g', '@openclaw/cli@latest'], environment: _getEnv());
    if (result.exitCode != 0) {
      print("[OpenClawSystem] Install OpenClaw failed: ${result.stderr}");
      throw Exception("Failed to install OpenClaw: ${result.stderr}");
    }
    print("[OpenClawSystem] Install OpenClaw success.");
  }

  static Future<void> installOllama() async {
    print("[OpenClawSystem] Installing Ollama via brew...");
    if (!Platform.isMacOS) throw Exception("Automatic Ollama install only supported on macOS");
    final result = await Process.run('brew', ['install', '--cask', 'ollama'], environment: _getEnv());
    if (result.exitCode != 0) {
      print("[OpenClawSystem] Install Ollama failed: ${result.stderr}");
      throw Exception("Failed to install Ollama via Homebrew: ${result.stderr}");
    }
    print("[OpenClawSystem] Install Ollama success.");
  }

  static Future<void> startOllama() async {
    print("[OpenClawSystem] Starting Ollama App...");
    if (!Platform.isMacOS) return;
    final result = await Process.run('open', ['-a', 'Ollama'], environment: _getEnv());
    if (result.exitCode != 0) {
      print("[OpenClawSystem] Start Ollama failed: ${result.stderr}");
      throw Exception("Failed to start Ollama App: ${result.stderr}");
    }
    
    print("[OpenClawSystem] Waiting for Ollama API to boot...");
    // Wait for it to boot (up to 15s)
    for (int i = 0; i < 15; i++) {
      try {
        final res = await http.get(Uri.parse('http://127.0.0.1:11434/api/tags'));
        if (res.statusCode == 200) {
          print("[OpenClawSystem] Ollama booted successfully.");
          return;
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 1));
    }
    print("[OpenClawSystem] Ollama boot timeout.");
    throw Exception("Ollama did not start in time.");
  }

  static Future<void> pullModel() async {
    print("[OpenClawSystem] Pulling model $modelName...");
    final result = await Process.run('ollama', ['pull', modelName], environment: _getEnv());
    if (result.exitCode != 0) {
      print("[OpenClawSystem] Model pull failed: ${result.stderr}");
      throw Exception("Failed to pull model $modelName: ${result.stderr}");
    }
    print("[OpenClawSystem] Model pull success.");
  }

  // --- GATEWAY ---

  static Future<bool> isGatewayRunning() async {
    try {
      final result = await _runOpenClaw(['gateway', 'status', '--json', '--no-probe']);
      
      // pnpm adds its own output before the actual command output, so we need to extract just the JSON part
      String output = result.stdout.toString().trim();
      if (output.isEmpty) {
        output = result.stderr.toString().trim();
      }
      
      // Find the first '{' character to start parsing JSON (skip pnpm's header)
      final jsonStart = output.indexOf('{');
      if (jsonStart == -1) {
        print("[OpenClawSystem] No JSON found in gateway status output: $output");
        return false;
      }
      
      final jsonOutput = output.substring(jsonStart);
      final json = jsonDecode(jsonOutput);
      final status = json['service']?['runtime']?['status'];
      final isRunning = status == 'running' || json['service']?['runtime']?['pid'] != null;
      print("[OpenClawSystem] Gateway status check: isRunning=$isRunning, status=$status, pid=${json['service']?['runtime']?['pid']}");
      return isRunning;
    } catch (e) {
      print("[OpenClawSystem] Gateway status check failed: $e");
      return false;
    }
  }

  static Future<void> startGatewayAndVerify() async {
    print("[OpenClawSystem] Checking if Gateway is already running...");
    if (await isGatewayRunning()) {
      print("[OpenClawSystem] Gateway is already running.");
      return;
    }

    print("[OpenClawSystem] Starting Gateway detached...");
    // Start detached
    await _startOpenClaw(['gateway', 'run', '--force']);

    print("[OpenClawSystem] Verifying Gateway startup...");
    // Verify it started (retry loop up to 10 seconds)
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (await isGatewayRunning()) {
        print("[OpenClawSystem] Gateway started and verified successfully.");
        return;
      }
    }
    
    print("[OpenClawSystem] Gateway verification timed out.");
    throw Exception("Gateway failed to start or verify within 10 seconds. Check if 'openclaw' CLI is accessible.");
  }

  static Future<void> enableGatewayAutostart() async {
    print("[OpenClawSystem] Enabling Gateway auto-start...");
    final result = await _runOpenClaw(['gateway', 'install', '--json']);
    if (result.exitCode != 0) {
      print("[OpenClawSystem] Enable auto-start failed: ${result.stderr}");
      throw Exception("Failed to enable auto-start: ${result.stderr}");
    }
    print("[OpenClawSystem] Auto-start enabled successfully.");
  }
}
