// tracking_models.dart
import 'dart:convert';

class TrackingInfo {
  final String trackingNumber;
  final String carrierCode;
  final String status;
  final String? weightValue;
  final String? weightUnit;
  final List<TrackingEvent> events;

  TrackingInfo({
    required this.trackingNumber,
    required this.carrierCode,
    required this.status,
    this.weightValue,
    this.weightUnit,
    required this.events,
  });

  factory TrackingInfo.fromFedExJson(String trackingNumber, Map<String, dynamic> json) {
    final trackResults = json['output']['completeTrackResults'][0]['trackResults'][0];
    final statusDetail = trackResults['latestStatusDetail'];

    // Extract weight
    String? weightValue;
    String? weightUnit;

    // Try to get from shipment details
    final shipmentWeight = trackResults['shipmentDetails']?['weight'] as List?;
    if (shipmentWeight != null && shipmentWeight.isNotEmpty) {
      weightValue = shipmentWeight[0]['value']?.toString();
      weightUnit = shipmentWeight[0]['unit']?.toString();
    }
    // If not found, try from package details
    else {
      final packageWeightList = trackResults['packageDetails']?['weightAndDimensions']?['weight'] as List?;
      if (packageWeightList != null && packageWeightList.isNotEmpty) {
        weightValue = packageWeightList[0]['value']?.toString();
        weightUnit = packageWeightList[0]['unit']?.toString();
      }
    }

    // Parse events
    final events = <TrackingEvent>[];
    final rawEvents = trackResults['scanEvents'] as List?;
    if (rawEvents != null) {
      for (var event in rawEvents) {
        final eventDate = DateTime.parse(event['date']).toLocal();
        final location = event['scanLocation']?['city'] ??
            event['locationType'] ??
            'Unknown location';

        events.add(TrackingEvent(
          description: event['eventDescription'] ?? 'Status update',
          date: "${eventDate.month}/${eventDate.day}/${eventDate.year}",
          time: "${eventDate.hour}:${eventDate.minute.toString().padLeft(2, '0')}",
          location: location,
        ));
      }
    }

    return TrackingInfo(
      trackingNumber: trackingNumber,
      carrierCode: "FedEx",
      status: statusDetail['statusByLocale'] ?? 'Unknown',
      weightValue: weightValue,
      weightUnit: weightUnit,
      events: events,
    );
  }

  factory TrackingInfo.fromUpsJson(String trackingNumber, Map<String, dynamic> json) {
    try {
      final trackResponse = json['trackResponse'];
      final shipment = trackResponse['shipment'][0];
      final package = shipment['package'][0];
      final activities = package['activity'] as List;

      // Get current status from the first activity
      final currentActivity = activities.isNotEmpty ? activities[0] : {};
      final statusObj = currentActivity['status'] ?? {};

      // Extract weight
      String? weightValue;
      String? weightUnit;
      final packageWeight = package['packageWeight'];
      if (packageWeight != null) {
        weightValue = packageWeight['weight']?.toString();
        final unitObj = packageWeight['unitOfMeasurement'] ?? {};
        weightUnit = unitObj['code']?.toString();
      }

      // Parse events
      final events = <TrackingEvent>[];
      for (var activity in activities) {
        final status = activity['status'] ?? {};
        final locationObj = activity['location'] ?? {};
        final address = locationObj['address'] ?? {};
        final date = activity['date'] ?? ''; // Format: YYYYMMDD
        final time = activity['time'] ?? ''; // Format: HHmmss

        // Format date
        String formattedDate = '';
        if (date.length == 8) {
          formattedDate = '${date.substring(4, 6)}/${date.substring(6, 8)}/${date.substring(0, 4)}';
        }

        // Format time
        String formattedTime = '';
        if (time.length >= 4) {
          formattedTime = '${time.substring(0, 2)}:${time.substring(2, 4)}';
        }

        events.add(TrackingEvent(
          description: status['description'] ?? 'Status update',
          date: formattedDate,
          time: formattedTime,
          location: address['city'] ?? 'Unknown location',
        ));
      }

      return TrackingInfo(
        trackingNumber: trackingNumber,
        carrierCode: "UPS",
        status: statusObj['description'] ?? 'Unknown',
        weightValue: weightValue,
        weightUnit: weightUnit,
        events: events,
      );
    } catch (e) {
      print('Error parsing UPS data: $e');
      rethrow;
    }
  }
}

class TrackingEvent {
  final String description;
  final String date;
  final String time;
  final String location;

  TrackingEvent({
    required this.description,
    required this.date,
    required this.time,
    required this.location,
  });
}