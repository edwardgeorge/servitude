from distutils.core import setup
from distutils.extension import Extension
from Cython.Distutils import build_ext

setup(
    name='servitude',
    packages=['servitude'],
    ext_modules=[Extension("servitude/servitudecoremidi",
        ["servitude/servitudecoremidi.pyx"],
        extra_link_args = [
            '-framework', 'CoreFoundation',
            '-framework', 'CoreMIDI'
    ]),],
    cmdclass = {'build_ext': build_ext}
)

