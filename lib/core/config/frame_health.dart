class FrameHealth {
  static const windowSize = 120;
  int frames = 0;
  int slow = 0;
  int maxBuildUs = 0;
  int maxRasterUs = 0;
  int _buildUs = 0;
  int _rasterUs = 0;
  int _windowFrames = 0;
  int _windowSlow = 0;

  bool add({required int buildUs, required int rasterUs, required double hz}) {
    if (buildUs < 0 || rasterUs < 0 || !hz.isFinite || hz < 30) return false;
    final budgetUs = 1000000 / hz;
    final delayed = buildUs > budgetUs * 1.25 || rasterUs > budgetUs * 1.25;
    frames++;
    _buildUs += buildUs;
    _rasterUs += rasterUs;
    if (delayed) slow++;
    if (buildUs > maxBuildUs) maxBuildUs = buildUs;
    if (rasterUs > maxRasterUs) maxRasterUs = rasterUs;
    _windowFrames++;
    if (delayed) _windowSlow++;
    if (_windowFrames < windowSize) return false;
    final reduce = _windowSlow >= windowSize * 0.15;
    resetWindow();
    return reduce;
  }

  void resetWindow() {
    _windowFrames = 0;
    _windowSlow = 0;
  }

  Map<String, int> get summary => {
    'frames': frames,
    'slow': slow,
    'mean_build_us': frames == 0 ? 0 : _buildUs ~/ frames,
    'mean_raster_us': frames == 0 ? 0 : _rasterUs ~/ frames,
    'max_build_us': maxBuildUs,
    'max_raster_us': maxRasterUs,
  };
}
