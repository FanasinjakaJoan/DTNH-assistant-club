import 'package:dtnh_assistant_club/data/auth/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const supabaseUrl = 'https://example.supabase.co';

  test('isProviderEnabled renvoie true quand le provider est activé', () async {
    final client = MockClient((request) async {
      expect(request.headers['apikey'], 'anon-key');
      expect(request.url.path, '/auth/v1/settings');
      return http.Response(
        '{"external":{"google":true,"email":true}}',
        200,
      );
    });

    final enabled = await AuthService.isProviderEnabled(
      'google',
      client: client,
      supabaseUrl: supabaseUrl,
      anonKey: 'anon-key',
    );

    expect(enabled, isTrue);
  });

  test('isProviderEnabled renvoie false quand le provider est désactivé',
      () async {
    final client = MockClient(
      (request) async => http.Response(
        '{"external":{"google":false,"email":true}}',
        200,
      ),
    );

    final enabled = await AuthService.isProviderEnabled(
      'google',
      client: client,
      supabaseUrl: supabaseUrl,
      anonKey: 'anon-key',
    );

    expect(enabled, isFalse);
  });

  test('isProviderEnabled renvoie null sur une réponse HTTP non-200',
      () async {
    final client = MockClient(
      (request) async => http.Response('boom', 500),
    );

    final enabled = await AuthService.isProviderEnabled(
      'google',
      client: client,
      supabaseUrl: supabaseUrl,
      anonKey: 'anon-key',
    );

    expect(enabled, isNull);
  });

  test('isProviderEnabled renvoie null sur un corps inattendu', () async {
    final client = MockClient(
      (request) async => http.Response('not json', 200),
    );

    final enabled = await AuthService.isProviderEnabled(
      'google',
      client: client,
      supabaseUrl: supabaseUrl,
      anonKey: 'anon-key',
    );

    expect(enabled, isNull);
  });

  test('isProviderEnabled renvoie null quand le réseau échoue', () async {
    final client = MockClient(
      (request) async => throw Exception('réseau indisponible'),
    );

    final enabled = await AuthService.isProviderEnabled(
      'google',
      client: client,
      supabaseUrl: supabaseUrl,
      anonKey: 'anon-key',
    );

    expect(enabled, isNull);
  });

  test('isProviderEnabled renvoie null quand le serveur ne répond pas',
      () async {
    final client = MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return http.Response('{"external":{"google":true}}', 200);
    });

    final enabled = await AuthService.isProviderEnabled(
      'google',
      client: client,
      supabaseUrl: supabaseUrl,
      anonKey: 'anon-key',
      timeout: const Duration(milliseconds: 50),
    );

    expect(enabled, isNull);
  });

  test('isProviderEnabled renvoie null si le provider est absent', () async {
    final client = MockClient(
      (request) async => http.Response('{"external":{"email":true}}', 200),
    );

    final enabled = await AuthService.isProviderEnabled(
      'google',
      client: client,
      supabaseUrl: supabaseUrl,
      anonKey: 'anon-key',
    );

    expect(enabled, isNull);
  });
}
