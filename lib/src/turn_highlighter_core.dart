import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';


class TurnHighlighter {
  final List<LatLng> path;
  final double turnThresholdAngleDeg;
  final double highlightRadiusMeters;
  final Color highlightColor;
  final int polylineWidth;
  final String? outdoorID;

  TurnHighlighter({
    required this.path,
    this.turnThresholdAngleDeg = 150.0,
    this.highlightRadiusMeters = 5.0,
    this.highlightColor = const Color(0xFFFFFFFF),
    this.polylineWidth = 6,
    this.outdoorID
  });

  /// Public method to get all white highlight polylines for turns
  List<Polyline> getTurnPolylines() {
    final List<int> turnIndices = _detectTurns();
    List<Polyline> result = [];

    List<LatLng>? lastSegment = null;

    for (int i = turnIndices.length-1; i >=0; i--) {
      final segment = _extractSegmentAround(turnIndices[i]);
      final end = segment.last;
      final prev = segment[segment.length - 2];

      var arrow;

      if(lastSegment != null){
        if(!_isNear(lastSegment, end)){
          // Direction of arrow
          final direction = Geolocator.bearingBetween(
            prev.latitude, prev.longitude,
            end.latitude, end.longitude,
          );
          // Add arrowhead points
          arrow = _createArrowHead(end, direction, 0.7); // 1.5 meters arrow wings
        }
        lastSegment = segment ;
      }else{
        lastSegment = segment ;
        // Direction of arrow
        final direction = Geolocator.bearingBetween(
          prev.latitude, prev.longitude,
          end.latitude, end.longitude,
        );
        // Add arrowhead points
        arrow = _createArrowHead(end, direction, 0.7); // 1.5 meters arrow wings
      }





      result.add(
        Polyline(
            polylineId: PolylineId("turn_blue_$i"),
            points: segment,
            color: Color(0xff141590),
            width: polylineWidth+3,
            zIndex: 5
        ),
      );

      if(arrow != null){
        result.add(
          Polyline(
              polylineId: PolylineId("turn_arrow_blue_$i"),
              points: [...arrow, arrow.first],
              color: Color(0xff141590),
              width: polylineWidth+1,
              zIndex: 5
          ),
        );
      }

      result.add(
        Polyline(
            polylineId: PolylineId("turn_$i"),
            points: segment,
            color: highlightColor,
            width: polylineWidth,
            zIndex: 5
        ),
      );

      if(arrow != null){
        result.add(
          Polyline(
              polylineId: PolylineId("turn_arrow_$i"),
              points: [...arrow, arrow.first],
              color: highlightColor,
              width: polylineWidth-2,
              zIndex: 5
          ),
        );
      }


    }

    return result;
  }

  /// Detect turn indices using angle threshold
  List<int> _detectTurns() {
    List<int> turns = [];
    for (int i = 1; i < path.length - 1; i++) {
      double angle = _angleBetween(path[i - 1], path[i], path[i + 1]);
      if (angle < turnThresholdAngleDeg) {
        turns.add(i);
      }
    }
    turns.remove(1);
    return turns;
  }

  /// Calculate angle (in degrees) between three points
  double _angleBetween(LatLng a, LatLng b, LatLng c) {
    double abx = b.longitude - a.longitude;
    double aby = b.latitude - a.latitude;
    double cbx = b.longitude - c.longitude;
    double cby = b.latitude - c.latitude;

    double dot = abx * cbx + aby * cby;
    double cross = abx * cby - aby * cbx;
    return (atan2(cross, dot) * 180 / pi).abs();
  }

  /// Extract a segment around a turn index spanning highlightRadiusMeters before and after
  List<LatLng> _extractSegmentAround(int turnIndex) {
    LatLng turnPoint = path[turnIndex];
    List<LatLng> segment = [];

    // Step 1: Get backward point
    if (turnIndex > 0) {
      double bearingBack = Geolocator.bearingBetween(
        path[turnIndex].latitude,
        path[turnIndex].longitude,
        path[turnIndex - 1].latitude,
        path[turnIndex - 1].longitude,
      );

      LatLng pointBefore = _moveInDirection(turnPoint, bearingBack, highlightRadiusMeters);
      segment.add(pointBefore);
    }

    // Step 2: Add actual turn point
    segment.add(turnPoint);

    // Step 3: Get forward point
    if (turnIndex < path.length - 1) {
      double bearingForward = Geolocator.bearingBetween(
        path[turnIndex].latitude,
        path[turnIndex].longitude,
        path[turnIndex + 1].latitude,
        path[turnIndex + 1].longitude,
      );

      LatLng pointAfter = _moveInDirection(turnPoint, bearingForward, highlightRadiusMeters);
      segment.add(pointAfter);
    }

    return segment;
  }

  LatLng _moveInDirection(LatLng from, double bearingDegrees, double distanceMeters) {
    const double earthRadius = 6371000; // meters
    final double distRadians = distanceMeters / earthRadius;
    final double bearing = bearingDegrees * pi / 180;

    final double lat1 = from.latitude * pi / 180;
    final double lon1 = from.longitude * pi / 180;

    final double lat2 = asin(sin(lat1) * cos(distRadians) +
        cos(lat1) * sin(distRadians) * cos(bearing));
    final double lon2 = lon1 +
        atan2(
          sin(bearing) * sin(distRadians) * cos(lat1),
          cos(distRadians) - sin(lat1) * sin(lat2),
        );

    return LatLng(lat2 * 180 / pi, lon2 * 180 / pi);
  }

  List<LatLng> _createArrowHead(LatLng tip, double directionDegrees, double lengthMeters) {
    // Left wing: -135°, Right wing: +125° from direction
    double leftBearing = (directionDegrees - 140) % 360;
    double rightBearing = (directionDegrees + 140) % 360;

    LatLng leftPoint = _moveInDirection(tip, leftBearing, lengthMeters);
    LatLng rightPoint = _moveInDirection(tip, rightBearing, lengthMeters);

    return [leftPoint, tip, rightPoint];
  }

  bool _isNear(List<LatLng> segment, LatLng p){
    for (var node in segment) {
      if(_calculateAerialDist(node.latitude, node.longitude, p.latitude, p.longitude) <= 1){
        return true;
      }
    }

    return false;
  }

  double _calculateAerialDist(double lat1, double lon1, double lat2, double lon2) {
    // Approximate conversion factor: 1 degree of latitude/longitude to meters
    const double metersPerDegree = 111320;

    // Calculate the differences
    double latDifference = lat2 - lat1;
    double lonDifference = lon2 - lon1;

    // Euclidean distance in degrees
    double distanceDegrees = sqrt(pow(latDifference, 2) + pow(lonDifference, 2));

    // Convert the distance from degrees to meters
    double distanceMeters = distanceDegrees * metersPerDegree;

    return distanceMeters;
  }

}