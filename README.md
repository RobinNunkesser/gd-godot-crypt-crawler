# Crypt Crawler (Godot 4)

> **Didaktisches Referenzprojekt für Vorlesung 16:** *Dungeons, Graphen & Topologie (IGA)*  
> **Hochschule Hamm-Lippstadt (HSHL)** | Prof. Dr. Robin Nunkesser

[![Test & Export](https://github.com/rnunkesser/gd-godot-crypt-crawler/actions/workflows/export.yml/badge.svg)](https://github.com/rnunkesser/gd-godot-crypt-crawler/actions/workflows/export.yml)

Ein 2D-Top-Down Roguelike- & Dungeon-Crawler in Godot 4, der die mathematischen und algorithmischen Grundlagen von Dungeontopologien, prozeduraler Generierung (BSP) und Schlüssel-Schloss-Kausalitäten (Lock-and-Key Puzzles) veranschaulicht.

---

## 🗝️ Kernfeatures

1. **VGLC (*Video Game Level Corpus*) DOT-Parser (`core/vglc_dot_parser.gd`):**
   - Parst Standard-Levelgraphen aus dem VGLC (*The Legend of Zelda*, Summerville et al., 2016).
   - Enthält den originalen Level 1 Graph (*"The Eagle"* - `levels/zelda_eagle.dot`) mit Raumtypen (`s`=Start, `k`=Key, `e`=Enemy, `b`=Boss, `t`=Triforce) und Kantentypen (`open`, `locked`, `shutter`, `bomb`).

2. **Prozedurale Generierung via Binary Space Partitioning (`core/bsp_dungeon_generator.gd`):**
   - Rekursive Zerlegung des Raums mit L-förmigen Korridorverbindungen.
   - Topologische Rollen- und Kantenvergabe unter Einhaltung der mathematischen DAG-Bedingung:
     $$\text{Tiefe}(\text{Schlüssel}) < \text{Tiefe}(\text{Tür})$$

3. **Mathematische Lösbarkeitsprüfung & Deadlock-Erkennung (`core/dungeon_graph.gd`):**
   - Traversierungs-Simulation zur Verifikation, ob ein Dungeon ohne Sackgassen mit den vorhandenen Schlüsseln beendbar ist.

4. **Live-Topologie & Gameplay:**
   - **Minimap-Overlay (`scripts/minimap_overlay.gd`):** Zeichnet den Graphen live mit Knoten- und Kantenstatus.
   - **Fog-of-War / Fackellicht (`scripts/fog_of_war.gd`):** Dynamisches 2D-Beleuchtungssystem mit `CanvasModulate` und `PointLight2D`.
   - **Spieler-Kinematik & Inventar (`scripts/player.gd`):** 8-Wege-Top-Down-Bewegung mit Kollisionsprüfung gegen Wände und verschlossene Türen.

---

## 🎮 Steuerung

| Taste | Aktion |
| :--- | :--- |
| **`[W] [A] [S] [D]` / Pfeiltasten** | Spieler bewegen |
| **`[1]`** | VGLC Zelda Level 1 (*The Eagle*) laden |
| **`[2]`** | Prozeduralen BSP-Dungeon generieren |
| **`[R]`** | Prozeduralen Dungeon mit neuem Seed auswürfeln |
| **`[M]`** | Topologie-Minimap ein-/ausblenden |
| **`[F]`** | Fackel / Fog-of-War umschalten |

---

## 🧪 Headless Tests ausführen

```bash
godot --headless -s test_gameplay.gd
```
