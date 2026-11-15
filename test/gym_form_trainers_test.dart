// Owner gym edit vs trainer links (fix 2026-11-11). Gym rows from
// GET /owner/gyms carry no trainer list, so the form used to open with no
// trainers selected and send `trainerIds: []`; the server treats that list as
// the gym's full set and unlinked every trainer on an ordinary edit. The form
// now loads the gym's linked trainers and sends `trainerIds` only when the
// owner changes that selection.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/shared/widgets/gym_form_page.dart';

import 'support/recording_api.dart';

const _owner = {'id': 'o1', 'userType': 'gym_owner'};

const _gym = {
  'id': 'g1',
  'name': 'Kilimani Gym',
  'location': 'Kilimani',
  'ratePerDay': 5000,
};

const _linked = [
  {
    'id': 't1',
    'displayName': 'Asha',
    'gymIds': ['g1'],
  },
  {
    'id': 't2',
    'displayName': 'Baraka',
    'gymIds': ['g1', 'g2'],
  },
];

/// Opens the form the way the owner's Manage gyms page does and sends its
/// result to PUT /owner/gyms/:id.
class _EditHost extends StatelessWidget {
  const _EditHost();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        key: const Key('open-edit'),
        onPressed: () async {
          final payload = await openGymForm(
            context,
            initial: Map<String, dynamic>.from(_gym),
          );
          if (payload == null || !context.mounted) return;
          await AppScope.of(context).api.ownerUpdateGym('g1', payload);
        },
        child: const Text('edit'),
      ),
    );
  }
}

Future<void> _openForm(WidgetTester tester, RecordingApi api) async {
  await pumpPage(tester, api, const _EditHost(), user: _owner);
  await tester.tap(find.byKey(const Key('open-edit')));
  await tester.pumpAndSettle();
}

Future<Map<String, dynamic>> _saveAndReadPut(
  WidgetTester tester,
  RecordingApi api,
) async {
  await tester.tap(find.byKey(const Key('gym-form-save')));
  await tester.pumpAndSettle();
  return Map<String, dynamic>.from(
    api.only('PUT', '/owner/gyms/g1').body! as Map,
  );
}

Future<void> _scrollTo(WidgetTester tester, Finder f) => tester
    .scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);

void main() {
  apiTest('an edit that leaves trainers alone sends no trainerIds', (
    tester,
    api,
  ) async {
    api.on('GET /owner/trainers', _linked);
    api.on('PUT /owner/gyms/g1', {'gym': _gym});
    await _openForm(tester, api);

    // Loads this gym's trainers (not the public trainer list) and selects them.
    final load = api.only('GET', '/owner/trainers');
    expect(load.query, 'gymId=g1');
    expect(api.sent('GET', '/trainers'), isFalse);
    await _scrollTo(tester, find.byKey(const Key('gym-trainer-chip-t1')));
    for (final id in ['t1', 't2']) {
      final chip = tester.widget<FilterChip>(
        find.byKey(Key('gym-trainer-chip-$id')),
      );
      expect(chip.selected, isTrue, reason: '$id should start selected');
    }

    // An ordinary edit: change the gym's name only.
    await tester.scrollUntilVisible(
      find.byType(TextFormField).first,
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextFormField).first, 'Kilimani Gym 2');
    final body = await _saveAndReadPut(tester, api);

    expect(body['name'], 'Kilimani Gym 2');
    expect(body.containsKey('trainerIds'), isFalse);
  });

  apiTest('unticking a linked trainer sends the remaining ones', (
    tester,
    api,
  ) async {
    api.on('GET /owner/trainers', _linked);
    api.on('PUT /owner/gyms/g1', {'gym': _gym});
    await _openForm(tester, api);

    final chip = find.byKey(const Key('gym-trainer-chip-t2'));
    await _scrollTo(tester, chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    final body = await _saveAndReadPut(tester, api);

    expect(body['trainerIds'], ['t1']);
  });

  apiTest('trainers of the owner\'s other gyms are not offered', (
    tester,
    api,
  ) async {
    // The server falls back to all the owner's gyms for an id it doesn't
    // match; the form keeps only trainers linked to this gym.
    api.on('GET /owner/trainers', [
      ..._linked,
      {
        'id': 't3',
        'displayName': 'Chausiku',
        'gymIds': ['g2'],
      },
    ]);
    api.on('PUT /owner/gyms/g1', {'gym': _gym});
    await _openForm(tester, api);

    await _scrollTo(tester, find.byKey(const Key('gym-trainer-chip-t1')));
    expect(find.byKey(const Key('gym-trainer-chip-t3')), findsNothing);
    final body = await _saveAndReadPut(tester, api);
    expect(body.containsKey('trainerIds'), isFalse);
  });

  apiTest('a failed trainer load offers no picker and keeps the links', (
    tester,
    api,
  ) async {
    api.fail('GET /owner/trainers');
    api.on('PUT /owner/gyms/g1', {'gym': _gym});
    await _openForm(tester, api);

    // No fallback to the public trainer list.
    expect(api.sent('GET', '/trainers'), isFalse);
    await _scrollTo(tester, find.byKey(const Key('gym-trainers-load-failed')));
    expect(find.byType(FilterChip), findsNothing);
    final body = await _saveAndReadPut(tester, api);
    expect(body.containsKey('trainerIds'), isFalse);
  });

  apiTest('a new gym points owners to join requests', (tester, api) async {
    await pumpPage(tester, api, const GymFormPage(), user: _owner);

    expect(api.sent('GET', '/owner/trainers'), isFalse);
    expect(api.sent('GET', '/trainers'), isFalse);
    await _scrollTo(tester, find.byKey(const Key('gym-trainers-join-hint')));
    expect(find.byType(FilterChip), findsNothing);
  });

  apiTest('the join hint has Swahili', (tester, api) async {
    final host = await pumpPage(
      tester,
      api,
      const GymFormPage(),
      user: _owner,
      lang: 'sw',
    );
    await _scrollTo(tester, find.byKey(const Key('gym-trainers-join-hint')));
    expect(host.tr('ownerReg.trainersJoinHint'), contains('ombi la kujiunga'));
    expect(find.text(host.tr('ownerReg.trainersJoinHint')), findsOneWidget);
  });
}
