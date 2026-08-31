import 'dart:io';

import 'package:lib_llama_cpp/lib_llama_cpp.dart';

class ReflectionResult {
  const ReflectionResult({
    required this.question,
    required this.isDemo,
    this.failure,
  });
  final String question;
  final bool isDemo;
  final Object? failure;
}

abstract interface class ReflectionService {
  Future<ReflectionResult> reflectOn(String text);
}

abstract interface class ThemeAnalysisService {
  Future<List<String>> extractThemes(String text);
}

abstract interface class EmbeddingService {
  Future<List<double>> embed(String text);
}

class AiService implements ReflectionService {
  AiService({String? modelPath})
    : modelPath =
          modelPath ??
          const String.fromEnvironment('SOTTO_MODEL_PATH', defaultValue: '');
  final String modelPath;

  bool get isConfigured => modelPath.isNotEmpty && File(modelPath).existsSync();

  @override
  Future<ReflectionResult> reflectOn(String text) async {
    if (!isConfigured) {
      return ReflectionResult(question: _demoQuestion(text), isDemo: true);
    }
    try {
      final client = LlamaOpenAIClient(
        models: {
          'companion': LlamaModelConfig(
            modelPath: modelPath,
            contextSize: 1024,
          ),
        },
      );
      final response = await client.responses.create(
        model: 'companion',
        instructions:
            'Output strictly ONE brief, Socratic reflection question under 12 words. Output only the question.',
        input: text,
        maxOutputTokens: 24,
        temperature: 0.65,
        stop: const ['\n'],
      );
      return ReflectionResult(
        question: _normalizeQuestion(response.outputText),
        isDemo: false,
      );
    } catch (error) {
      return ReflectionResult(
        question: _demoQuestion(text),
        isDemo: true,
        failure: error,
      );
    }
  }

  String _normalizeQuestion(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'''^[\s"'“”]+|[\s"'“”]+$'''), '')
        .split('\n')
        .first
        .trim();
    final words = cleaned
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    final limited = words.take(11).join(' ').replaceAll(RegExp(r'[.!]+$'), '');
    if (limited.isEmpty) return 'What feels most true here?';
    return limited.endsWith('?') ? limited : '$limited?';
  }

  String _demoQuestion(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('should') || lower.contains('must')) {
      return 'Whose expectation are you carrying here?';
    }
    if (lower.contains('want') || lower.contains('hope')) {
      return 'What would make that desire feel honest?';
    }
    if (lower.contains('afraid') || lower.contains('worry')) {
      return 'What might this fear be protecting?';
    }
    return 'What feels most alive beneath these words?';
  }
}
