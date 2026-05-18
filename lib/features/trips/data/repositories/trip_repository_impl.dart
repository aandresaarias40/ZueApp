import '../../../../models/trip_model.dart';
import '../../../../services/trip_service.dart';

class TripRepositoryImpl {
  final TripService _tripService = TripService();

  Future<TripModel> createTripRequest({
    required String passengerId,
    required String passengerName,
    required double originLat,
    required double originLng,
    required String originAddress,
    required double destinationLat,
    required double destinationLng,
    required String destinationAddress,
  }) =>
      _tripService.createTripRequest(
        passengerId: passengerId,
        passengerName: passengerName,
        originLat: originLat,
        originLng: originLng,
        originAddress: originAddress,
        destinationLat: destinationLat,
        destinationLng: destinationLng,
        destinationAddress: destinationAddress,
      );
}
