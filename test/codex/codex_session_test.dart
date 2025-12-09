import 'package:test/test.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_session.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_types.dart';

void main() {
  group('CodexRpcException', () {
    test('parses error with all fields', () {
      final error = {
        'code': -32600,
        'message': 'Invalid request',
        'data': {'details': 'missing field'},
      };

      final exception = CodexRpcException(error);

      expect(exception.code, -32600);
      expect(exception.message, 'Invalid request');
      expect(exception.data, {'details': 'missing field'});
      expect(exception.toString(), 'CodexRpcException: [-32600] Invalid request');
    });

    test('handles missing code field', () {
      final error = {'message': 'Some error'};

      final exception = CodexRpcException(error);

      expect(exception.code, -1);
      expect(exception.message, 'Some error');
    });

    test('handles missing message field', () {
      final error = {'code': 100};

      final exception = CodexRpcException(error);

      expect(exception.code, 100);
      expect(exception.message, 'Unknown error');
    });

    test('handles empty error map', () {
      final error = <String, dynamic>{};

      final exception = CodexRpcException(error);

      expect(exception.code, -1);
      expect(exception.message, 'Unknown error');
      expect(exception.data, isNull);
    });

    test('handles null data field', () {
      final error = {
        'code': 500,
        'message': 'Server error',
        'data': null,
      };

      final exception = CodexRpcException(error);

      expect(exception.data, isNull);
    });
  });

  group('CodexApprovalDecision', () {
    test('all decision values exist', () {
      expect(CodexApprovalDecision.values, hasLength(4));
      expect(CodexApprovalDecision.values, contains(CodexApprovalDecision.allow));
      expect(CodexApprovalDecision.values, contains(CodexApprovalDecision.deny));
      expect(CodexApprovalDecision.values, contains(CodexApprovalDecision.allowAlways));
      expect(CodexApprovalDecision.values, contains(CodexApprovalDecision.denyAlways));
    });
  });

  group('CodexApprovalRequest', () {
    test('creates from JSON with all fields', () {
      final json = {
        'id': 'approval_123',
        'turnId': 'turn_456',
        'actionType': 'shell',
        'description': 'Execute command: ls -la',
        'toolName': 'bash',
        'toolInput': {'command': 'ls -la'},
        'command': 'ls -la',
        'filePath': null,
      };

      final request = CodexApprovalRequest.fromJson(json);

      expect(request.id, 'approval_123');
      expect(request.turnId, 'turn_456');
      expect(request.actionType, 'shell');
      expect(request.description, 'Execute command: ls -la');
      expect(request.toolName, 'bash');
      expect(request.command, 'ls -la');
    });

    test('creates from JSON with file operation', () {
      final json = {
        'id': 'approval_789',
        'turnId': 'turn_101',
        'actionType': 'file_write',
        'description': 'Write to file: config.json',
        'toolName': 'write',
        'toolInput': {'path': 'config.json', 'content': '{}'},
        'command': null,
        'filePath': 'config.json',
      };

      final request = CodexApprovalRequest.fromJson(json);

      expect(request.actionType, 'file_write');
      expect(request.filePath, 'config.json');
      expect(request.command, isNull);
    });

    test('serializes to JSON and back', () {
      final original = CodexApprovalRequest(
        id: 'test_id',
        turnId: 'test_turn',
        actionType: 'shell',
        description: 'Test description',
        toolName: 'bash',
        toolInput: {'key': 'value'},
        command: 'echo test',
      );

      final json = original.toJson();
      final restored = CodexApprovalRequest.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.turnId, original.turnId);
      expect(restored.actionType, original.actionType);
      expect(restored.description, original.description);
      expect(restored.toolName, original.toolName);
      expect(restored.command, original.command);
    });
  });

  group('CodexApprovalResponse', () {
    test('creates with decision only', () {
      final response = CodexApprovalResponse(
        decision: CodexApprovalDecision.allow,
      );

      expect(response.decision, CodexApprovalDecision.allow);
      expect(response.message, isNull);
    });

    test('creates with decision and message', () {
      final response = CodexApprovalResponse(
        decision: CodexApprovalDecision.deny,
        message: 'Not allowed in this context',
      );

      expect(response.decision, CodexApprovalDecision.deny);
      expect(response.message, 'Not allowed in this context');
    });

    test('serializes to JSON and back', () {
      final original = CodexApprovalResponse(
        decision: CodexApprovalDecision.allowAlways,
        message: 'Approved for session',
      );

      final json = original.toJson();
      final restored = CodexApprovalResponse.fromJson(json);

      expect(restored.decision, original.decision);
      expect(restored.message, original.message);
    });
  });
}
