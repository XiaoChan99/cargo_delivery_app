class CargoDelivery {
  final String id;
  final String deliveryId;
  final String cargoId;
  final String confirmedBy;
  final DateTime confirmedAt;
  final String remarks;
  final String status;
  final String assignedTo;
  final String pickupLocation;
  final String destination;
  final DateTime createdAt;
  final String containerType;
  final String contents;
  final String weight;
  final String estimatedDistance;
  final String estimatedTime;

  CargoDelivery({
    required this.id,
    required this.deliveryId,
    required this.cargoId,
    required this.confirmedBy,
    required this.confirmedAt,
    required this.remarks,
    required this.status,
    required this.assignedTo,
    required this.pickupLocation,
    required this.destination,
    required this.createdAt,
    this.containerType = '20ft Standard',
    this.contents = '',
    this.weight = '',
    this.estimatedDistance = '',
    this.estimatedTime = '',
  });

  factory CargoDelivery.fromFirestore(Map<String, dynamic> data, String id) {
    return CargoDelivery(
      id: id,
      deliveryId: data['delivery_id'] ?? '',
      cargoId: data['cargo_id'] ?? '',
      confirmedBy: data['confirmed_by'] ?? '',
      confirmedAt: DateTime.parse(data['confirmed_at']),
      remarks: data['remarks'] ?? '',
      status: data['status'] ?? 'pending',
      assignedTo: data['assigned_to'] ?? '',
      pickupLocation: data['pickup_location'] ?? '',
      destination: data['destination'] ?? '',
      createdAt: DateTime.parse(data['created_at']),
      containerType: data['container_type'] ?? '20ft Standard',
      contents: data['contents'] ?? '',
      weight: data['weight'] ?? '',
      estimatedDistance: data['estimated_distance'] ?? '',
      estimatedTime: data['estimated_time'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'delivery_id': deliveryId,
      'cargo_id': cargoId,
      'confirmed_by': confirmedBy,
      'confirmed_at': confirmedAt.toIso8601String(),
      'remarks': remarks,
      'status': status,
      'assigned_to': assignedTo,
      'pickup_location': pickupLocation,
      'destination': destination,
      'created_at': createdAt.toIso8601String(),
      'container_type': containerType,
      'contents': contents,
      'weight': weight,
      'estimated_distance': estimatedDistance,
      'estimated_time': estimatedTime,
    };
  }
}