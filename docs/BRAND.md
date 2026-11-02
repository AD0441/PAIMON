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


## Portada y mensaje de familia · noviembre de 2026

La cabecera de familia del 1 de noviembre de 2026 se conserva en `docs/assets/brand/family-cover.png` como recurso gráfico anterior. Adopta el sistema común de [NABERIUS, RAZIEL, METATRON, PAIMON y VAPULA](FAMILY.md): azul petróleo, marfil, acento azul apagado, mensaje a la izquierda y sello propio a la derecha.

**Simplicidad con impacto. Concéntrate en lo que vale la pena.** El eslogan específico de PAIMON es **Del sonido al conocimiento.**

Es una ilustración promocional generada con imagegen sobre los recursos de marca existentes. El [prompt y la procedencia](assets/brand/family-cover-prompt.md) documentan su elaboración. Los iconos de aplicación, la geometría vectorial original, las capturas reales y los recursos anteriores se conservan. Los generadores históricos siguen produciendo sus archivos originales; la nueva portada se mantiene como recurso independiente.


## Portada fotográfica · 2 de noviembre de 2026

La cabecera actual es [photographic-cover.png](assets/promo/photographic-cover.png). El logo oficial aparece encima del nombre, seguido del eslogan y «Simplicidad con impacto.». La fotografía, el encuadre y los objetos se adaptan al propósito de cada app: Estudio de audio al atardecer, micrófono, audífonos y paneles acústicos.

Es una composición promocional creada con la herramienta integrada de generación de imágenes, tomando la interfaz y el logo propios como referencias. La imagen final puede reinterpretar detalles de pantalla; no constituye una captura íntegra ni una validación de funciones. Las [fuentes, los prompts y el alcance](assets/promo/photographic-cover.md) quedan documentados. Los iconos oficiales, las capturas originales y las portadas anteriores se conservan.
