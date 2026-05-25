import 'package:cloud_firestore/cloud_firestore.dart';

class TripModel {
  final String id;
  final String passengerId;
  final String passengerName;
  final String? driverId;
  final String? driverName;
  final String? driverPhone;
  final String? vehiclePlate;
  final String? vehicleType;          // Tipo de vehículo del conductor que aceptó
  final String? requestedVehicleType; // Tipo de vehículo solicitado por el pasajero
  final double originLat;
  final double originLng;
  final String originAddress;
  final double destinationLat;
  final double destinationLng;
  final String destinationAddress;
  final String status;
  final double? fare;          // Tarifa del viaje
  final double? distance;      // Distancia en km
  final int? duration;         // Duración en minutos
  final int? passengerRating;
  final int? driverRating;
  final String? passengerComment;
  final String? cancelReason;
  final String? assignmentType; // auto, manual
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  const TripModel({
    required this.id,
    required this.passengerId,
    required this.passengerName,
    this.driverId,
    this.driverName,
    this.driverPhone,
    this.vehiclePlate,
    this.vehicleType,
    this.requestedVehicleType,
    required this.originLat,
    required this.originLng,
    required this.originAddress,
    required this.destinationLat,
    required this.destinationLng,
    required this.destinationAddress,
    required this.status,
    this.fare,
    this.distance,
    this.duration,
    this.passengerRating,
    this.driverRating,
    this.passengerComment,
    this.cancelReason,
    this.assignmentType,
    required this.createdAt,
    this.acceptedAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
  });

  factory TripModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TripModel(
      id: doc.id,
      passengerId: data['passengerId'] ?? '',
      passengerName: data['passengerName'] ?? '',
      driverId: data['driverId'],
      driverName: data['driverName'],
      driverPhone: data['driverPhone'],
      vehiclePlate: data['vehiclePlate'],
      vehicleType: data['vehicleType'],
      requestedVehicleType: data['requestedVehicleType'],
      originLat: (data['originLat'] ?? 0.0).toDouble(),
      originLng: (data['originLng'] ?? 0.0).toDouble(),
      originAddress: data['originAddress'] ?? '',
      destinationLat: (data['destinationLat'] ?? 0.0).toDouble(),
      destinationLng: (data['destinationLng'] ?? 0.0).toDouble(),
      destinationAddress: data['destinationAddress'] ?? '',
      status: data['status'] ?? 'requested',
      fare: data['fare']?.toDouble(),
      distance: data['distance']?.toDouble(),
      duration: data['duration'],
      passengerRating: data['passengerRating'],
      driverRating: data['driverRating'],
      passengerComment: data['passengerComment'],
      cancelReason: data['cancelReason'],
      assignmentType: data['assignmentType'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      acceptedAt: (data['acceptedAt'] as Timestamp?)?.toDate(),
      startedAt: (data['startedAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      cancelledAt: (data['cancelledAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'passengerId': passengerId,
      'passengerName': passengerName,
      'driverId': driverId,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'vehiclePlate': vehiclePlate,
      'vehicleType': vehicleType,
      'requestedVehicleType': requestedVehicleType,
      'originLat': originLat,
      'originLng': originLng,
      'originAddress': originAddress,
      'destinationLat': destinationLat,
      'destinationLng': destinationLng,
      'destinationAddress': destinationAddress,
      'status': status,
      'fare': fare,
      'distance': distance,
      'duration': duration,
      'passengerRating': passengerRating,
      'driverRating': driverRating,
      'passengerComment': passengerComment,
      'cancelReason': cancelReason,
      'assignmentType': assignmentType,
      'createdAt': Timestamp.fromDate(createdAt),
      'acceptedAt': acceptedAt != null ? Timestamp.fromDate(acceptedAt!) : null,
      'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'cancelledAt': cancelledAt != null ? Timestamp.fromDate(cancelledAt!) : null,
    };
  }
}
