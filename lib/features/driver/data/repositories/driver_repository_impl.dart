import '../../../../models/driver_model.dart';
import '../../../../services/driver_service.dart';

class DriverRepositoryImpl {
  final DriverService _driverService = DriverService();

  Future<DriverModel> getDriverById(String driverId) =>
      _driverService.getDriverById(driverId);

  Stream<DriverModel> watchDriver(String driverId) =>
      _driverService.watchDriver(driverId);
}
