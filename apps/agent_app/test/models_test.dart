import 'package:agent_app/features/collections/data/collections_data.dart';
import 'package:agent_app/features/dashboard/data/dashboard_data.dart';
import 'package:agent_app/features/deliveries/data/deliveries_data.dart';
import 'package:agent_app/features/kyc/data/kyc_data.dart';
import 'package:agent_app/features/notifications/data/notifications_data.dart';
import 'package:agent_app/features/verification/data/verification_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentDelivery.fromMap', () {
    test('accepts camelCase and snake_case + nested customer', () {
      final d = AgentDelivery.fromMap({
        'id': '7',
        'order_code': 'ORD1',
        'status': 'out_for_delivery',
        'customer': {'name': 'Asha', 'phone': '+9199'},
        'dest_lat': '17.4',
        'destLng': 78.4,
      });
      expect(d.id, '7');
      expect(d.orderCode, 'ORD1');
      expect(d.customerName, 'Asha');
      expect(d.destLat, 17.4);
      expect(d.destLng, 78.4);
    });

    test('is null-safe on an empty map', () {
      final d = AgentDelivery.fromMap({});
      expect(d.id, '');
      expect(d.destLat, isNull);
    });
  });

  group('AgentCollection.fromMap', () {
    test('parses amounts null-safely', () {
      final c = AgentCollection.fromMap({'id': '3', 'status': 'assigned'});
      expect(c.id, '3');
      expect(c.status, 'assigned');
    });
  });

  group('VerificationTask.fromMap', () {
    test('camel/snake id + type', () {
      final t = VerificationTask.fromMap({
        'id': '9',
        'customer_id': '12',
        'type': 'kyc',
        'status': 'assigned',
      });
      expect(t.id, '9');
      expect(t.customerId, '12');
      expect(t.type, 'kyc');
    });
  });

  group('KycDoc.fromMap', () {
    test('hasFile is true only when a url is present; filePath is auth-gated', () {
      final withFile = KycDoc.fromMap({
        'id': '5',
        'type': 'pan',
        'number_masked': 'XXXXX1234F',
        'status': 'pending',
        'url': 'https://host/media/kyc/5/pan/p.jpg',
      });
      expect(withFile.hasFile, isTrue);
      expect(withFile.filePath, '/kyc/documents/5/file');

      final noFile = KycDoc.fromMap({'id': '6', 'type': 'aadhaar', 'status': 'pending'});
      expect(noFile.hasFile, isFalse);
    });
  });

  group('AppNotification.fromMap', () {
    test('isRead derives from readAt when is_read absent; keeps data map', () {
      final n = AppNotification.fromMap({
        'id': '1',
        'type': 'delivery',
        'title': 'New delivery',
        'read_at': '2026-07-08T10:00:00Z',
        'data': {'taskId': 42, 'orderCode': 'ORD9'},
      });
      expect(n.isRead, isTrue);
      expect(n.data['orderCode'], 'ORD9');
      expect(n.type, 'delivery');
    });

    test('unread when no readAt', () {
      final n = AppNotification.fromMap({'id': '2', 'type': 'payment'});
      expect(n.isRead, isFalse);
    });
  });

  group('AgentProfile / AgentAttendance', () {
    test('profile parses availability + pincodes across casings', () {
      final p = AgentProfile.fromMap({
        'id': '1',
        'name': 'Ravi',
        'is_available': true,
        'assigned_pincodes': ['500001', '500002'],
      });
      expect(p.isAvailable, isTrue);
      expect(p.assignedPincodes, ['500001', '500002']);
      expect(p.displayName, 'Ravi');
    });

    test('attendance checkedIn/checkedOut derive from timestamps', () {
      final a = AgentAttendance.fromMap({
        'date': '2026-07-08',
        'check_in_at': '09:00',
        'on_duty': true,
      });
      expect(a.checkedIn, isTrue);
      expect(a.checkedOut, isFalse);
      expect(a.onDuty, isTrue);
    });
  });
}
