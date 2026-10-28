# Identidad de PAIMON

El icono interpreta de forma geométrica el [sello de Paimon de The Goetia (Mathers, 1904)](https://commons.wikimedia.org/wiki/File:Paimon_Seal.jpg), catalogado como dominio público. La versión simplificada usa cuatro círculos superiores, diagonales paralelas, dos barras, terminales circulares y un solo contorno. Omite volutas y caligrafía; no es un facsímil.

Comparte con [METATRON](https://github.com/AD0441/METATRON) el azul profundo `#111C27`, el marfil `#E8E7D7` y una composición geométrica sobria, manteniendo un símbolo propio.

- `Resources/Brand/PAIMON-icon.svg`: fuente vectorial del icono.
- `Resources/Brand/PAIMON-symbol.svg`: símbolo sin fondo.
- `Resources/Brand/PAIMON-symbol.png`: símbolo monolineal transparente para el pie de la interfaz.
- `Resources/Brand/PAIMON-icon.png`: imagen de 1024 px con márgenes transparentes.
- `Resources/Paimon.icns`: icono de macOS, de 16 a 1024 px.
- `docs/images/paimon-cover.png`: portada de GitHub.

Regenera los recursos localmente con AppKit y Core Graphics:

```bash
xcrun swift script/render_brand.swift
./script/rebuild_icon.sh
```

Las cuatro paletas de la app cambian los acentos; los fondos y colores funcionales siguen el sistema. Ko-fi se muestra como enlace local y no descarga recursos al iniciar.

**Creado por Sebastián Pastén F.**
