"""Share the media popup's spectrum with the desktop widgets (after the light-mode patches)."""
import os
import sys
sys.path.insert(0, os.path.dirname(__file__))
from edit import edit

root = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')
file = os.path.join(root, 'modules', 'ii', 'mediaControls', 'MediaControls.qml')
with open(file, encoding='utf-8') as f:
    source = f.read()
start = source.index('    Process {\n        id: cavaProc\n')
end = source.index('\n    Loader {', start)
edit(file, [
    ('    property list<real> visualizerPoints: []',
     '    property list<real> visualizerPoints: spectrum.active ? AudioSpectrum.points : []'),
    (source[start:end], '''    AudioSpectrumClient {
        id: spectrum
        active: mediaControlsLoader.active && !Config.options.appearance.reduceMotion
    }
'''),
])
