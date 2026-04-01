import 'dart:convert';
import 'dart:io';

class OpenClawConfig {
  // Instead of manually writing config, we'll use openclaw CLI commands
  
  static Future<void> configureForArny({
    required String gatewayToken,
    required String backendUrl,
    required String assistantName,
  }) async {
    print("[OpenClawConfig] Configuring OpenClaw via CLI commands...");
    
    final root = await _getRepoRoot();
    final env = _getEnv();
    
    try {
      // Set gateway auth token
      print("[OpenClawConfig] Setting gateway auth token...");
      await Process.run('pnpm', ['openclaw', 'config', 'set', 'gateway.auth.mode', 'token'], 
          workingDirectory: root, environment: env);
      await Process.run('pnpm', ['openclaw', 'config', 'set', 'gateway.auth.token', gatewayToken], 
          workingDirectory: root, environment: env);
      
      // Set backend URL in environment
      print("[OpenClawConfig] Setting backend URL...");
      await Process.run('pnpm', ['openclaw', 'config', 'set', 'env.vars.OPENCLAW_ARNY_BACKEND_URL', backendUrl], 
          workingDirectory: root, environment: env);
      
      // Set Ollama API key
      print("[OpenClawConfig] Setting Ollama API key...");
      await Process.run('pnpm', ['openclaw', 'config', 'set', 'env.vars.OLLAMA_API_KEY', 'ollama-local'], 
          workingDirectory: root, environment: env);
      
      // Set default model
      print("[OpenClawConfig] Setting default model...");
      await Process.run('pnpm', ['openclaw', 'config', 'set', 'agents.defaults.model', 'ollama/qwen3.5:0.8b'], 
          workingDirectory: root, environment: env);
      
      // Set assistant name if provided
      if (assistantName.isNotEmpty) {
        print("[OpenClawConfig] Setting assistant name...");
        await Process.run('pnpm', ['openclaw', 'config', 'set', 'ui.assistant.name', assistantName], 
            workingDirectory: root, environment: env);
      }
      
      // Disable web interface
      print("[OpenClawConfig] Disabling web interface...");
      await Process.run('pnpm', ['openclaw', 'config', 'set', 'web.enabled', 'false'], 
          workingDirectory: root, environment: env);
      
      print("[OpenClawConfig] Configuration completed successfully.");
      
    } catch (e) {
      print("[OpenClawConfig] Configuration failed: $e");
      throw Exception("Failed to configure OpenClaw: $e");
    }
  }
  
  static Future<String> _getRepoRoot() async {
    final dir = Directory.current;
    if (dir.path.endsWith('arny_setup_wizard')) {
      return dir.parent.parent.path;
    }
    return '/Users/ckc/Documents/github/dev/arny_openclaw';
  }
  
  static Map<String, String> _getEnv() {
    final env = Map<String, String>.from(Platform.environment);
    env['PATH'] = '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${env['PATH'] ?? ''}';
    return env;
  }
}
