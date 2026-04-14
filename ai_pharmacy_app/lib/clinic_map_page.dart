import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class ClinicMapPage extends StatefulWidget {
  final String clinicId;
  const ClinicMapPage({Key? key, required this.clinicId}) : super(key: key);

  @override
  _ClinicMapPageState createState() => _ClinicMapPageState();
}

class _ClinicMapPageState extends State<ClinicMapPage> {
  final String baseUrl = "http://localhost:5000";
  bool isLoading = true;
  String? errorMessage;
  List<dynamic> clinics = [];
  Map<String, dynamic>? selectedClinic;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    fetchClinicNetwork();
  }

  Future<void> fetchClinicNetwork() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final res = await http.get(
        Uri.parse("$baseUrl/clinic_network?clinic_id=${widget.clinicId}"),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final list = List<dynamic>.from(data['clinics'] ?? []);
        setState(() {
          clinics = list;
          // Auto-select logged-in clinic
          selectedClinic = list.firstWhere(
            (c) => c['is_self'] == true,
            orElse: () => list.isNotEmpty ? list[0] : null,
          );
        });
      } else {
        setState(() => errorMessage = "Server error: ${res.statusCode}");
      }
    } catch (e) {
      setState(() => errorMessage = "Connection failed. Is the backend running?");
      print("ERROR ClinicMap: $e");
    }
    setState(() => isLoading = false);
  }

  String _weatherIcon(String condition) {
    switch (condition) {
      case 'Clear Sky':     return '☀️';
      case 'Partly Cloudy': return '⛅';
      case 'Rainy':         return '🌧️';
      case 'Heavy Rain':    return '⛈️';
      case 'Thunderstorm':  return '🌩️';
      case 'Snowy':         return '❄️';
      default:              return '🌤️';
    }
  }

  Color _weatherColor(String condition) {
    switch (condition) {
      case 'Clear Sky':     return const Color(0xFFFBBF24);
      case 'Partly Cloudy': return const Color(0xFF94A3B8);
      case 'Rainy':         return const Color(0xFF60A5FA);
      case 'Heavy Rain':    return const Color(0xFF818CF8);
      case 'Thunderstorm':  return const Color(0xFFA78BFA);
      default:              return const Color(0xFF34D399);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        color: const Color(0xFF0F172A),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
      );
    }

    if (errorMessage != null) {
      return Container(
        color: const Color(0xFF0F172A),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(errorMessage!, style: const TextStyle(color: Colors.white54, fontSize: 16)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: fetchClinicNetwork,
                icon: const Icon(Icons.refresh),
                label: const Text("Retry"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
              ),
            ],
          ),
        ),
      );
    }

    final myClinic = clinics.firstWhere(
      (c) => c['is_self'] == true,
      orElse: () => clinics.isNotEmpty ? clinics[0] : {'lat': 3.1390, 'lng': 101.6869},
    );
    final LatLng mapCenter = LatLng(myClinic['lat'] as double, myClinic['lng'] as double);

    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── LEFT: MAP PANEL (65%) ─────────────────────────────────────
          Expanded(
            flex: 65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Clinic Network",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Live map, distances & weather for all clinics",
                          style: TextStyle(color: Colors.cyanAccent.withOpacity(0.8), fontSize: 13),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Legend
                    _buildLegendChip(Colors.cyanAccent, "Your Clinic"),
                    const SizedBox(width: 12),
                    _buildLegendChip(Colors.amber, "Selected"),
                    const SizedBox(width: 12),
                    _buildLegendChip(Colors.white70, "Other Clinics"),
                    const SizedBox(width: 16),
                    IconButton(
                      onPressed: fetchClinicNetwork,
                      icon: const Icon(Icons.refresh_rounded, color: Colors.cyanAccent),
                      tooltip: "Refresh",
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Map
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: mapCenter,
                            initialZoom: 11.5,
                          ),
                          children: [
                            // Dark tile layer (CartoDB Dark Matter)
                            TileLayer(
                              urlTemplate:
                                  'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                              subdomains: const ['a', 'b', 'c', 'd'],
                              userAgentPackageName: 'com.ai_pharmacy_app',
                            ),
                            // Clinic markers
                            MarkerLayer(
                              markers: clinics.map<Marker>((clinic) {
                                final isSelf = clinic['is_self'] == true;
                                final isSelected =
                                    selectedClinic?['clinic_id'] == clinic['clinic_id'];
                                final color = isSelf
                                    ? Colors.cyanAccent
                                    : (isSelected ? Colors.amber : Colors.white);

                                return Marker(
                                  point: LatLng(
                                    clinic['lat'] as double,
                                    clinic['lng'] as double,
                                  ),
                                  width: 130,
                                  height: 72,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() => selectedClinic = clinic);
                                      _mapController.move(
                                        LatLng(clinic['lat'] as double, clinic['lng'] as double),
                                        13.5,
                                      );
                                    },
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Label bubble
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: color.withOpacity(isSelf || isSelected ? 0.95 : 0.85),
                                            borderRadius: BorderRadius.circular(10),
                                            boxShadow: [
                                              BoxShadow(
                                                color: color.withOpacity(0.5),
                                                blurRadius: isSelf ? 12 : 6,
                                                spreadRadius: isSelf ? 2 : 0,
                                              )
                                            ],
                                          ),
                                          child: Text(
                                            clinic['clinic_id'],
                                            style: const TextStyle(
                                              color: Colors.black87,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        // Pin icon
                                        Icon(
                                          Icons.location_on,
                                          color: color,
                                          size: 28,
                                          shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),

                        // Selected clinic info popup (bottom-left overlay)
                        if (selectedClinic != null)
                          Positioned(
                            bottom: 16,
                            left: 16,
                            child: _buildMapPopup(selectedClinic!),
                          ),

                        // OpenStreetMap attribution (required)
                        Positioned(
                          bottom: 4,
                          right: 8,
                          child: Text(
                            "© CartoDB | © OpenStreetMap contributors",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 20),

          // ─── RIGHT: CLINIC LIST PANEL (35%) ──────────────────────────
          Expanded(
            flex: 35,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "All Clinics",
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          "Tap a card to focus on map",
                          style: TextStyle(color: Colors.blueGrey[400], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: clinics.length,
                      itemBuilder: (context, i) => _buildClinicCard(clinics[i]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── HELPERS ────────────────────────────────────────────────────────────────

  Widget _buildLegendChip(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }

  Widget _buildMapPopup(Map<String, dynamic> clinic) {
    final weather = clinic['weather'] as Map<String, dynamic>? ?? {};
    final condition = weather['condition'] as String? ?? 'Unknown';
    final temp = weather['temperature'];
    final rain = weather['rain_mm'] ?? 0;
    final isSelf = clinic['is_self'] == true;

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.97),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelf ? Colors.cyanAccent.withOpacity(0.5) : Colors.white12,
          width: 1.5,
        ),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.local_pharmacy, color: isSelf ? Colors.cyanAccent : Colors.white70, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  clinic['name'] ?? clinic['clinic_id'],
                  style: TextStyle(
                    color: isSelf ? Colors.cyanAccent : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "${_weatherIcon(condition)}  $condition${temp != null ? '  ·  ${temp}°C' : ''}",
            style: TextStyle(color: _weatherColor(condition), fontSize: 13, fontWeight: FontWeight.w500),
          ),
          if ((rain as num) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text("🌧️ $rain mm precipitation", style: const TextStyle(color: Colors.blue, fontSize: 11)),
            ),
          if (!isSelf)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(Icons.directions, color: Colors.blueGrey, size: 13),
                  const SizedBox(width: 4),
                  Text("${clinic['distance_km']} km from your clinic",
                      style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
                ],
              ),
            ),
          if (isSelf)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text("📍 Your location", style: TextStyle(color: Colors.cyanAccent, fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _buildClinicCard(Map<String, dynamic> clinic) {
    final isSelf = clinic['is_self'] == true;
    final isSelected = selectedClinic?['clinic_id'] == clinic['clinic_id'];
    final weather = clinic['weather'] as Map<String, dynamic>? ?? {};
    final condition = weather['condition'] as String? ?? 'Unknown';
    final temp = weather['temperature'];
    final rain = weather['rain_mm'] ?? 0;
    final dist = clinic['distance_km'];

    return GestureDetector(
      onTap: () {
        setState(() => selectedClinic = clinic);
        _mapController.move(
          LatLng(clinic['lat'] as double, clinic['lng'] as double),
          13.5,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelf
                ? Colors.cyanAccent.withOpacity(0.6)
                : (isSelected ? Colors.amber.withOpacity(0.4) : Colors.transparent),
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.cyanAccent.withOpacity(0.05), blurRadius: 10)]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Clinic name row
            Row(
              children: [
                Icon(Icons.local_pharmacy, color: isSelf ? Colors.cyanAccent : Colors.white70, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    clinic['name'] ?? clinic['clinic_id'],
                    style: TextStyle(
                      color: isSelf ? Colors.cyanAccent : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelf)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
                    ),
                    child: const Text("You", style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 4),

            // Area
            if (clinic['area'] != null)
              Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 6),
                child: Text(clinic['area'], style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ),

            // Weather row
            Row(
              children: [
                Text(_weatherIcon(condition), style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "${condition}${temp != null ? '  ·  ${temp}°C' : ''}",
                    style: TextStyle(color: _weatherColor(condition), fontSize: 12, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            // Rain badge
            if ((rain as num) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Text("🌧️ $rain mm precipitation",
                      style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 11)),
                ),
              ),

            // Distance
            if (!isSelf && dist != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(Icons.directions, color: Colors.blueGrey, size: 13),
                    const SizedBox(width: 4),
                    Text("$dist km away",
                        style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
