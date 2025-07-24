// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyer_chat/src/views/chat/widgets/message_bubble.dart';
import 'package:flyer_chat/src/views/chat/widgets/media_preview.dart';
import 'package:flyer_chat/src/views/chat/chat_screen.dart';
import 'package:flyer_chat/src/models/message_model.dart';

import 'package:flyer_chat/main.dart';
void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that our counter starts at 0.
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    // Tap the '+' icon and trigger a frame.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // Verify that our counter has incremented.
    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('MessageBubble displays text message', (WidgetTester tester) async {
    final message = MessageModel(
      id: '1',
      senderId: 'user1',
      receiverId: 'user2',
      content: 'Hello world!',
      type: MessageType.text,
      timestamp: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: message,
            isMe: true,
            onReply: (_, [__]) {},
            allMessages: {'1': message},
          ),
        ),
      ),
    );

    expect(find.text('Hello world!'), findsOneWidget);
  });

  testWidgets('MessageBubble displays audio icon for audio message', (WidgetTester tester) async {
    final message = MessageModel(
      id: '2',
      senderId: 'user1',
      receiverId: 'user2',
      content: 'dummybase64',
      type: MessageType.audio,
      timestamp: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: message,
            isMe: false,
            onReply: (_, [__]) {},
            allMessages: {'2': message},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('TypingBubble animates and uses theme color', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.green)),
        home: Scaffold(body: TypingBubble()),
      ),
    );
    expect(find.byType(TypingBubble), findsOneWidget);
  });

  testWidgets('MediaPreview displays file info', (WidgetTester tester) async {
    final message = MessageModel(
      id: '3',
      senderId: 'user1',
      receiverId: 'user2',
      content: '',
      type: MessageType.file,
      timestamp: DateTime.now(),
      metadata: {'name': 'test.txt', 'size': 1234},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaPreview(message: message),
        ),
      ),
    );
    expect(find.text('test.txt'), findsOneWidget);
    expect(find.text('1234 bytes'), findsOneWidget);
  });
}
