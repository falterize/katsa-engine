"""Prepares the PBR maps of the Duke 69 for SurfaceAppearance3D (colorMap, normalMap,
roughnessMap, metalnessMap): resizes them and turns the height maps into tangent-space normals.

    python tools/import/carMaps.py <textures dir of the model zip> <output dir>

The engine reads grey roughness/metalness maps directly, so the specular map of the car paint
becomes a roughness map by inversion.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image

SIZE = 512
NORMAL_STRENGTH = 3.0

# group -> { map: source file }
GROUPS = {
    'bottom': dict(color='UCB_BOTTOM_LT_DIF.jpg', height='UCB_BOTTOM_LT_Height.jpg', metal='UCB_BOTTOM_LT_Met.jpg', rough='UCB_BOTTOM_LT_Rough.jpg'),
    'interior': dict(color='UCB_Interiors_2_Dif.jpg', height='UCB_Interiors_2_Height.jpg', metal='UCB_Interiors_2_Met.jpg', rough='UCB_Interiors_2_Rough.jpg'),
    'tire': dict(color='RB1c_Tire_1k_Dif.jpg', height='RB1c_Tire_1k_Height.jpg', metal='RB1c_Tire_1k_Met.jpg', rough='RB1c_Tire_1k_Rough.jpg'),
    'plate': dict(color='Numberplates_Misk_U_Dif.png', height='Numberplates_Misk_U_Height.png'),
    'badges': dict(color='Carbadges_misc_U_dif.png', height='Carbadges_misc_U_height.jpg'),
    'lights': dict(color='UCB_Lights_and_Glass_Dif.jpg'),
    'paint': dict(metal='Carpaint_Gen_tile20_Met.png', rough_from_spec='Carpaint_Gen_tile20_Spec.png'),
}


def load(path, size=SIZE):
    image = Image.open(path)
    if image.width != size:
        image = image.resize((size, size), Image.LANCZOS)
    return image


def normal_from_height(height):
    h = np.asarray(height.convert('L'), dtype=np.float32) / 255.0
    # Wrapping differences: the maps are tiled textures.
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * NORMAL_STRENGTH * SIZE / 64
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * NORMAL_STRENGTH * SIZE / 64
    n = np.stack([-dx, dy, np.ones_like(h)], -1)  # +y up in the image: glTF/OpenGL convention
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8), 'RGB')


def main(source, output):
    source, output = Path(source), Path(output)
    output.mkdir(parents=True, exist_ok=True)
    for group, files in GROUPS.items():
        for kind, name in files.items():
            image = load(source / name)
            if kind == 'color':
                if image.mode == 'RGBA':
                    image.save(output / f'{group}_color.png', optimize=True)
                else:
                    image.convert('RGB').save(output / f'{group}_color.jpg', quality=88)
            elif kind == 'height':
                normal_from_height(image).save(output / f'{group}_normal.png', optimize=True)
            elif kind == 'rough_from_spec':
                inverted = Image.eval(image.convert('L'), lambda v: 255 - v)
                inverted.save(output / f'{group}_rough.png', optimize=True)
            else:
                image.convert('L').save(output / f'{group}_{kind}.png', optimize=True)
    print('wrote', len(list(output.iterdir())), 'maps to', output)


if __name__ == '__main__':
    main(*sys.argv[1:3])
