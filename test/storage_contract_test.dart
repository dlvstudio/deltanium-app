import 'dart:convert';

import 'package:deltanium_app/models/storage_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StorageContract', () {
    group('fromJson', () {
      test('parses contractHash from JSON', () {
        final json = {
          'contractId': 'cid1',
          'contractType': 'OpenEnded',
          'appPublicKey': 'appPK',
          'storageNodePublicKey': 'nodePK',
          'startDateUnix': 1000,
          'endDateUnix': null,
          'totalFileSize': 1024,
          'totalFee': 0.0000001,
          'fileIds': <String>['f1'],
          'contractHash': 'abc123hex',
          'messageToSign': '',
          'appSignature': '',
          'storageNodeSignature': '',
          'createdAtUnix': 1000,
          'status': 'Active',
        };

        final c = StorageContract.fromJson(json);

        expect(c.contractHash, 'abc123hex');
        expect(c.contractId, 'cid1');
        expect(c.appPublicKey, 'appPK');
        expect(c.storageNodePublicKey, 'nodePK');
      });

      test('defaults contractHash to empty when missing', () {
        final json = {
          'contractId': 'c',
          'contractType': 'OpenEnded',
          'appPublicKey': 'a',
          'storageNodePublicKey': 'b',
          'startDateUnix': 0,
          'totalFileSize': 0,
          'totalFee': 0.0,
          'fileIds': <String>[],
          'messageToSign': '',
          'appSignature': '',
          'storageNodeSignature': '',
          'createdAtUnix': 0,
          'status': 'Active',
        };

        final c = StorageContract.fromJson(json);

        expect(c.contractHash, '');
      });
    });

    group('buildCanonicalContractJson', () {
      test('includes appPublicKey and storageNodePublicKey', () {
        final json = StorageContract.buildCanonicalContractJson(
          contractId: 'cid',
          contractType: 'OpenEnded',
          appPublicKey: 'appPK',
          storageNodePublicKey: 'nodePK',
          startDateUnix: 1000,
          endDateUnix: null,
          totalFileSize: 1024,
          totalFee: 0.0000001,
          fileIds: ['f1'],
          createdAtUnix: 500,
          status: 'Active',
        );

        final map = jsonDecode(json) as Map<String, dynamic>;
        expect(map['appPublicKey'], 'appPK');
        expect(map['storageNodePublicKey'], 'nodePK');
        expect(map.containsKey('contractHash'), false);
        expect(map.containsKey('appSignature'), false);
      });

      test('sorts fileIds alphabetically', () {
        final json = StorageContract.buildCanonicalContractJson(
          contractId: 'c',
          contractType: 'OpenEnded',
          appPublicKey: 'a',
          storageNodePublicKey: 'b',
          startDateUnix: 0,
          totalFileSize: 0,
          totalFee: 0.0,
          fileIds: ['z', 'a', 'm'],
          createdAtUnix: 0,
          status: 'Active',
        );

        final map = jsonDecode(json) as Map<String, dynamic>;
        final ids = (map['fileIds'] as List<dynamic>).cast<String>();
        expect(ids, ['a', 'm', 'z']);
      });

      test('OpenEnded omits endDateUnix', () {
        final json = StorageContract.buildCanonicalContractJson(
          contractId: 'c',
          contractType: 'OpenEnded',
          appPublicKey: 'a',
          storageNodePublicKey: 'b',
          startDateUnix: 0,
          endDateUnix: null,
          totalFileSize: 0,
          totalFee: 0.0,
          fileIds: [],
          createdAtUnix: 0,
          status: 'Active',
        );

        final map = jsonDecode(json) as Map<String, dynamic>;
        expect(map.containsKey('endDateUnix'), false);
      });

      test('TimeFixed includes endDateUnix', () {
        final json = StorageContract.buildCanonicalContractJson(
          contractId: 'c',
          contractType: 'TimeFixed',
          appPublicKey: 'a',
          storageNodePublicKey: 'b',
          startDateUnix: 100,
          endDateUnix: 200,
          totalFileSize: 0,
          totalFee: 0.0,
          fileIds: [],
          createdAtUnix: 0,
          status: 'Active',
        );

        final map = jsonDecode(json) as Map<String, dynamic>;
        expect(map['endDateUnix'], 200);
      });

      test('uses feeStringForHash when provided', () {
        final json = StorageContract.buildCanonicalContractJson(
          contractId: 'c',
          contractType: 'OpenEnded',
          appPublicKey: 'a',
          storageNodePublicKey: 'b',
          startDateUnix: 0,
          totalFileSize: 0,
          totalFee: 0.123456789,
          feeStringForHash: '0.0000001000',
          fileIds: [],
          createdAtUnix: 0,
          status: 'Active',
        );

        final map = jsonDecode(json) as Map<String, dynamic>;
        expect(map['totalFee'], '0.0000001000');
      });
    });

    group('computeContractHash', () {
      test('is deterministic for same contract', () {
        final c = StorageContract(
          contractId: 'cid',
          contractType: 'OpenEnded',
          appPublicKey: 'app',
          storageNodePublicKey: 'node',
          startDateUnix: 1,
          endDateUnix: null,
          totalFileSize: 100,
          totalFee: 0.1,
          totalFeeCanonical: '0.1000000000',
          fileIds: ['f1'],
          contractHash: '',
          messageToSign: '',
          appSignature: '',
          storageNodeSignature: '',
          createdAtUnix: 1,
          status: 'Active',
        );

        final hash1 = StorageContract.computeContractHash(c);
        final hash2 = StorageContract.computeContractHash(c);

        expect(hash1, hash2);
        expect(hash1.length, 64);
        expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(hash1), true);
      });

      test('different content produces different hash', () {
        final c1 = StorageContract(
          contractId: 'id1',
          contractType: 'OpenEnded',
          appPublicKey: 'a',
          storageNodePublicKey: 'b',
          startDateUnix: 0,
          totalFileSize: 0,
          totalFee: 0.0,
          fileIds: [],
          contractHash: '',
          messageToSign: '',
          appSignature: '',
          storageNodeSignature: '',
          createdAtUnix: 0,
          status: 'Active',
        );
        final c2 = StorageContract(
          contractId: 'id2',
          contractType: 'OpenEnded',
          appPublicKey: 'a',
          storageNodePublicKey: 'b',
          startDateUnix: 0,
          totalFileSize: 0,
          totalFee: 0.0,
          fileIds: [],
          contractHash: '',
          messageToSign: '',
          appSignature: '',
          storageNodeSignature: '',
          createdAtUnix: 0,
          status: 'Active',
        );

        expect(StorageContract.computeContractHash(c1), isNot(StorageContract.computeContractHash(c2)));
      });
    });

    group('generateMessageToSign', () {
      test('TimeFixed requires endDate', () {
        expect(
          () => StorageContract.generateMessageToSign(
            contractType: 'TimeFixed',
            startDate: 1,
            endDate: null,
            appPublicKey: 'a',
            storageNodePublicKey: 'b',
            totalFee: 0.0,
            totalFileSize: 0,
          ),
          throwsArgumentError,
        );
      });

      test('OpenEnded format contains startDate and fee', () {
        final msg = StorageContract.generateMessageToSign(
          contractType: 'OpenEnded',
          startDate: 1000,
          endDate: null,
          appPublicKey: 'app',
          storageNodePublicKey: 'node',
          totalFee: 0.0000001,
          totalFileSize: 2048,
        );
        expect(msg, contains('OpenEnded'));
        expect(msg, contains('1000'));
        expect(msg, contains('0.0000001000'));
      });
    });
  });
}
