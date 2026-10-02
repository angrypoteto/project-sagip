part of 'mock_mobile_backend.dart';

/// Sample alerts and 72-hour forecasts for the Alerts tab (R7, R8). The
/// real alerts come from the PAGASA, PHIVOLCS, and MDRRMD feeds; the real
/// forecast from the LSTM + KDE model (plan 10.5), run daily.
class _AlertsSim {
  _AlertsSim(this._b) : _updatedAt = _b._clock();

  final MockMobileBackend _b;
  final _version = LiveValue<int>(0);
  final _read = <String>{'alert-phivolcs-1'};

  /// When the phone last received the feed. Stays put while offline, so
  /// the tab can say "Last updated 2:15 PM".
  DateTime _updatedAt;

  Stream<AlertFeed> watch() => _version.watch().map((_) => _feed());

  void _bump() => _version.value++;

  Future<void> refresh() async {
    await _b._pause();
    if (_b._signal.value != SignalState.internet) {
      throw const ActionRejected(ActionRejection.offline);
    }
    _updatedAt = _b._clock();
    _bump();
  }

  Future<void> markRead(String id) async {
    if (_read.add(id)) _bump();
  }

  /// The phone is back online: the feed is current again.
  void onOnline() {
    _updatedAt = _b._clock();
    _bump();
  }

  /// The signed-in resident changed, so the forecast's barangay did too.
  void onAccountChanged() => _bump();

  AlertFeed _feed() {
    final home = _b._homeResident;
    return AlertFeed(
      alerts: [
        for (final a in _alerts()) a.copyWith(read: _read.contains(a.id)),
      ],
      forecast: home == null ? null : _forecast(home.barangay, home.district),
      updatedAt: _updatedAt,
    );
  }

  DateTime _ago(Duration d) => _b._t0.subtract(d);

  List<PublicAlert> _alerts() => [
    PublicAlert(
      id: 'alert-mdrrmd-1',
      source: AlertSource.mdrrmd,
      level: AlertLevel.warning,
      title: 'Flooding on Dapitan St and España Blvd',
      body:
          'Rescue teams are responding to knee-deep flooding along Dapitan '
          'St. Avoid the area if you can. If you need rescue, hold the SOS '
          'button in the app.',
      issuedAt: _ago(const Duration(minutes: 25)),
      barangays: const ['Barangay 412', 'Barangay 490'],
      guidance: const [
        'Do not walk or drive through floodwater.',
        'Keep your phone charged in case you need to send an SOS.',
      ],
    ),
    PublicAlert(
      id: 'alert-pagasa-rain',
      source: AlertSource.pagasa,
      level: AlertLevel.warning,
      title: 'Orange rainfall warning for Metro Manila',
      body:
          'Heavy rain of 15 to 30 mm per hour is falling and may continue '
          'for the next 3 hours. Flooding is threatening low-lying areas.',
      issuedAt: _ago(const Duration(minutes: 50)),
      guidance: const [
        'Move appliances and important papers to a higher place.',
        'Avoid wading in floodwater; it can carry disease and live wires.',
        'Prepare a go-bag with water, food, medicine, and a flashlight.',
      ],
    ),
    PublicAlert(
      id: 'alert-pagasa-tc',
      source: AlertSource.pagasa,
      level: AlertLevel.warning,
      title: 'Wind Signal No. 2 raised over Metro Manila',
      body:
          'A severe tropical storm may bring gale-force winds of 62 to 88 km '
          'per hour within 24 hours. Light structures and trees may be '
          'damaged.',
      issuedAt: _ago(const Duration(hours: 3)),
      guidance: const [
        'Secure or bring in loose objects outside your home.',
        'Stay indoors unless MDRRMD tells you to leave.',
      ],
    ),
    PublicAlert(
      id: 'alert-phivolcs-1',
      source: AlertSource.phivolcs,
      level: AlertLevel.info,
      title: 'Taal Volcano advisory: possible light ashfall',
      body:
          'PHIVOLCS reports steam and gas emission from Taal Volcano. Light '
          'ashfall may reach parts of Metro Manila depending on the wind.',
      issuedAt: _ago(const Duration(days: 1, hours: 2)),
      guidance: const [
        'If ash falls, wear a face mask or a damp cloth over your nose and '
            'mouth.',
        'Keep windows and doors closed.',
      ],
    ),
  ];

  /// The sample forecast for one barangay ([MockSeed.forecasts]); null for
  /// a barangay that has none.
  BarangayForecast? _forecast(String barangay, String district) {
    for (final f in MockSeed(_b._t0).forecasts) {
      if (f.barangay == barangay) return f;
    }
    return null;
  }
}
