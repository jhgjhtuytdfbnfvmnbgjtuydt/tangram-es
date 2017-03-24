//
//  TGMarker.mm
//  TangramMap
//
//  Created by Karim Naaji on 2/17/17.
//  Copyright (c) 2017 Mapzen. All rights reserved.
//

#import "TGMarker.h"
#import "TGMapViewController.h"
#import "TGMapViewController+Internal.h"
#import "TGHelpers.h"
#import "tangram.h"

enum class TGMarkerType {
    point,
    polygon,
    polyline,
    none,
};

@interface TGMarker () {
    Tangram::Map* tangramInstance;
    TGMapViewController* mapViewController;
    Tangram::MarkerID identifier;
    TGMarkerType type;
}

@property (copy, nonatomic) NSString* stylingString;
@property (copy, nonatomic) NSString* stylingPath;
@property (assign, nonatomic) TGGeoPoint point;
@property (strong, nonatomic) TGGeoPolyline* polyline;
@property (strong, nonatomic) TGGeoPolygon* polygon;
@property (assign, nonatomic) BOOL visible;
@property (assign, nonatomic) NSInteger drawOrder;
@property (strong, nonatomic) UIImage* icon;
@property (weak, nonatomic) TGMapViewController* map;

@end

@implementation TGMarker

- (instancetype)init
{
    self = [super init];

    if (self) {
        type = TGMarkerType::none;
        self.visible = YES;
        self.drawOrder = 0;
    }

    return self;
}

- (instancetype)initWithMapView:(TGMapViewController *)mapView
{
    self = [super init];

    if (self) {
        type = TGMarkerType::none;
        self.visible = YES;
        self.drawOrder = 0;
        self.map = mapView;
    }

    return self;
}

- (BOOL)setStylingString:(NSString *)styling
{
    _stylingString = styling;
    _stylingPath = nil;

    if (!tangramInstance || !identifier) { return; }

    return tangramInstance->markerSetStylingFromString(identifier, [styling UTF8String]);
}

- (BOOL)setStylingPath:(NSString *)path
{
    _stylingPath = path;
    _stylingString = nil;

    if (!tangramInstance || !identifier) { return; }

    return tangramInstance->markerSetStylingFromPath(identifier, [path UTF8String]);
}

- (BOOL)setPoint:(TGGeoPoint)coordinates
{
    _point = coordinates;
    type = TGMarkerType::point;

    if (!tangramInstance || !identifier) { return; }

    Tangram::LngLat lngLat(coordinates.longitude, coordinates.latitude);

    return tangramInstance->markerSetPoint(identifier, lngLat);
}

- (BOOL)setPointEased:(TGGeoPoint)coordinates seconds:(float)seconds easeType:(TGEaseType)ease
{
    _point = coordinates;
    type = TGMarkerType::point;

    if (!tangramInstance || !identifier) { return; }

    Tangram::LngLat lngLat(coordinates.longitude, coordinates.latitude);

    return tangramInstance->markerSetPointEased(identifier, lngLat, seconds, [TGHelpers convertEaseTypeFrom:ease]);
}

- (BOOL)setPolyline:(TGGeoPolyline *)polyline
{
    _polyline = polyline;
    type = TGMarkerType::polyline;

    if (polyline.count < 2 || !tangramInstance || !identifier) { return; }

    return tangramInstance->markerSetPolyline(identifier,
        reinterpret_cast<Tangram::LngLat*>([polyline coordinates]), polyline.count);
}

- (BOOL)setPolygon:(TGGeoPolygon *)polygon
{
    _polygon = polygon;
    type = TGMarkerType::polygon;

    if (polygon.count < 3 || !tangramInstance || !identifier) { return; }

    auto coords = reinterpret_cast<Tangram::LngLat*>([polygon coordinates]);

    return tangramInstance->markerSetPolygon(identifier, coords, [polygon rings], [polygon ringsCount]);
}

- (BOOL)setVisible:(BOOL)visible
{
    _visible = visible;

    if (!tangramInstance || !identifier) { return; }

    return tangramInstance->markerSetVisible(identifier, visible);
}

- (BOOL)setDrawOrder:(NSInteger)drawOrder
{
    _drawOrder = drawOrder;

    if (!tangramInstance || !identifier) { return; }

    return tangramInstance->markerSetDrawOrder(identifier, (int)drawOrder);
}

- (BOOL)setIcon:(UIImage *)icon
{
    _icon = icon;

    if (!tangramInstance) { return; }

    CGImage* cgImage = [icon CGImage];
    size_t w = CGImageGetHeight(cgImage);
    size_t h = CGImageGetWidth(cgImage);
    std::vector<unsigned int> bitmap;

    bitmap.resize(w * h);

    CGColorSpaceRef colorSpace = CGImageGetColorSpace(cgImage);
    CGContextRef cgContext = CGBitmapContextCreate(bitmap.data(), w, h, 8, w * 4,
        colorSpace, kCGImageAlphaPremultipliedLast);

    // Flip image upside down-horizontally
    CGAffineTransform flipAffineTransform = CGAffineTransformMake(1, 0, 0, -1, 0, h);
    CGContextConcatCTM(cgContext, flipAffineTransform);

    CGContextDrawImage(cgContext, CGRectMake(0, 0, w, h), cgImage);
    CGContextRelease(cgContext);

    return tangramInstance->markerSetBitmap(identifier, w, h, bitmap.data());
}

- (BOOL)setMap:(TGMapViewController *)mapView
{
    // remove marker from current view
    if (!mapView && tangramInstance && identifier) {
        if (!tangramInstance->markerRemove(identifier)) { return NO; }
        tangramInstance = nullptr;
        mapViewController = nil;
        return YES;
    }

    if (![mapView map] || [mapView map] == tangramInstance) { return NO; }

    // Removes the marker from the previous map view
    if (tangramInstance && mapViewController) {
        if (!tangramInstance->markerRemove(identifier)) { return NO; }
        [mapViewController removeMarker:identifier];
    }

    tangramInstance = [mapView map];
    mapViewController = mapView;

    // Create a new marker identifier for this view
    identifier = tangramInstance->markerAdd();
    [mapViewController addMarker:self withIdentifier:identifier];

    if (!identifier) { return NO; }

    // Set the geometry type
    switch (type) {
        case TGMarkerType::point: {
            [self setPoint:self.point];

            if (self.icon) {
                [self setIcon:self.icon];
            }
        }
        break;
        case TGMarkerType::polygon: {
            [self setPolygon:self.polygon];
        }
        break;
        case TGMarkerType::polyline: {
            [self setPolyline:self.polyline];
        }
        case TGMarkerType::none:
        break;
    }

    // Update styling
    if (self.stylingString) {
        if (!tangramInstance->markerSetStylingFromString(identifier, [self.stylingString UTF8String])) { return NO; }
    }
    if (self.stylingPath) {
        if (!tangramInstance->markerSetStylingFromPath(identifier, [self.stylingPath UTF8String]) { return NO; }
    }

    if (!tangramInstance->markerSetVisible(identifier, self.visible)) { return NO; }
    if (!tangramInstance->markerSetDrawOrder(identifier, (int)self.drawOrder)) { return NO; }

    return YES;
}

@end

