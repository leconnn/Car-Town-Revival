// Server copy of scripts/rules/garage_grid.gd.
import type { Catalog, Dict } from "./catalog.ts";

export const CAT_WORK_BAY = 5;
export const CAT_FLOOR_TILE = 6;
export const CAT_WALL = 7;
const CAT_WALL_ART = 8;
const CAT_DOOR = 10;
const CAT_WINDOW = 11;
export const CAT_SIGNAGE = 13;
const NON_FLOOR = [CAT_FLOOR_TILE, CAT_WALL, CAT_WALL_ART, CAT_DOOR, CAT_WINDOW, CAT_SIGNAGE];
const WALL_OBJECT_CATEGORIES = [CAT_WALL_ART, CAT_SIGNAGE];
export const VERTICAL = 0;
export const HORIZONTAL = 1;

export type Size = { x: number; y: number };

export function isFloorObject(def: Dict): boolean {
  return !NON_FLOOR.includes(def.category ?? 0) && (def.size_x ?? 0) > 0 && (def.size_y ?? 0) > 0;
}

export function isWall(def: Dict): boolean {
  return (def.category ?? 0) === CAT_WALL;
}

export function isWallObject(def: Dict): boolean {
  return WALL_OBJECT_CATEGORIES.includes(def.category ?? 0);
}

export function wallLength(def: Dict): number {
  return Math.max(1, def.size_y ?? 0);
}

export function wallObjectLength(def: Dict): number {
  return Math.max(1, def.size_x ?? 0);
}

export function rotatedSize(sx: number, sy: number, rot: number): Size {
  return rot % 2 === 1 ? { x: sy, y: sx } : { x: sx, y: sy };
}

function segment(x: number, y: number, i: number, horizontal: boolean): string {
  return horizontal ? `H:${x + i},${y}` : `V:${x},${y + i}`;
}

export class GarageGrid {
  cells = new Map<string, string>();
  wallsV = new Map<string, number>();
  wallsH = new Map<string, number>();
  halfWalls = new Map<number, boolean>();
  posters = new Map<string, number>();
  width: number;
  height: number;

  constructor(width: number, height: number) {
    this.width = width;
    this.height = height;
  }

  static build(catalog: Catalog, save: Dict): GarageGrid {
    const land = catalog.land(save.garage.land_id);
    const grid = new GarageGrid(land.size_x ?? 10, land.size_y ?? 10);
    for (const it of save.garage.items) {
      const def = catalog.item(it.item_id);
      if (!isFloorObject(def)) continue;
      grid.occupy(it.x, it.y, rotatedSize(def.size_x, def.size_y, it.rot), `item:${it.uid}`);
    }
    const carSize = catalog.tune("garage.car_size", [4, 3]);
    for (const c of save.cars) {
      if (c.placed && (c.bay_uid ?? 0) === 0) {
        grid.occupy(c.x, c.y, rotatedSize(carSize[0], carSize[1], c.rot), `car:${c.uid}`);
      }
    }
    for (const w of save.garage.walls ?? []) {
      const def = catalog.item(w.item_id);
      grid.addWall(w.x, w.y, wallLength(def), w.rot === HORIZONTAL, w.uid, def.half_wall ?? false);
    }
    for (const p of save.garage.wall_items ?? []) {
      grid.addPoster(p.x, p.y, wallObjectLength(catalog.item(p.item_id)), p.rot === HORIZONTAL, p.uid);
    }
    return grid;
  }

  occupy(x: number, y: number, size: Size, k: string): void {
    for (let dx = 0; dx < size.x; dx++) {
      for (let dy = 0; dy < size.y; dy++) this.cells.set(`${x + dx},${y + dy}`, k);
    }
  }

  occupant(x: number, y: number): string {
    return this.cells.get(`${x},${y}`) ?? "";
  }

  canPlace(x: number, y: number, size: Size, ignoreKey = ""): boolean {
    if (x < 0 || y < 0 || x + size.x > this.width || y + size.y > this.height) return false;
    for (let dx = 0; dx < size.x; dx++) {
      for (let dy = 0; dy < size.y; dy++) {
        const cell = `${x + dx},${y + dy}`;
        const owner = this.cells.get(cell) ?? "";
        if (owner !== "" && owner !== ignoreKey) return false;
        if (dx > 0 && this.wallsV.has(cell)) return false;
        if (dy > 0 && this.wallsH.has(cell)) return false;
      }
    }
    return true;
  }

  findFree(size: Size): { x: number; y: number } {
    for (let y = 0; y < this.height - size.y + 1; y++) {
      for (let x = 0; x < this.width - size.x + 1; x++) {
        if (this.canPlace(x, y, size)) return { x, y };
      }
    }
    return { x: -1, y: -1 };
  }

  addWall(x: number, y: number, length: number, horizontal: boolean, uid: number, half: boolean): void {
    for (let i = 0; i < length; i++) {
      if (horizontal) this.wallsH.set(`${x + i},${y}`, uid);
      else this.wallsV.set(`${x},${y + i}`, uid);
    }
    this.halfWalls.set(uid, half);
  }

  wallAt(x: number, y: number, horizontal: boolean): number {
    return (horizontal ? this.wallsH : this.wallsV).get(`${x},${y}`) ?? 0;
  }

  canPlaceWall(x: number, y: number, length: number, horizontal: boolean, ignoreUid = 0): boolean {
    if (x < 0 || y < 0) return false;
    if (horizontal && (x + length > this.width || y >= this.height)) return false;
    if (!horizontal && (y + length > this.height || x >= this.width)) return false;
    for (let i = 0; i < length; i++) {
      const cx = horizontal ? x + i : x;
      const cy = horizontal ? y : y + i;
      const here = this.wallAt(cx, cy, horizontal);
      if (here !== 0 && here !== ignoreUid) return false;
      const ox = horizontal ? cx : cx - 1;
      const oy = horizontal ? cy - 1 : cy;
      if (ox >= 0 && oy >= 0) {
        const a = this.occupant(ox, oy);
        if (a !== "" && a === this.occupant(cx, cy)) return false;
        if (i > 0) {
          const cross = this.wallAt(cx, cy, !horizontal);
          if (cross !== 0 && cross !== ignoreUid && cross === this.wallAt(ox, oy, !horizontal)) return false;
        }
      }
    }
    return true;
  }

  addPoster(x: number, y: number, length: number, horizontal: boolean, uid: number): void {
    for (let i = 0; i < length; i++) this.posters.set(segment(x, y, i, horizontal), uid);
  }

  canPlacePoster(x: number, y: number, length: number, horizontal: boolean, ignoreUid = 0): boolean {
    for (let i = 0; i < length; i++) {
      const cx = horizontal ? x + i : x;
      const cy = horizontal ? y : y + i;
      const wall = this.wallAt(cx, cy, horizontal);
      if (wall === 0 || (this.halfWalls.get(wall) ?? false)) return false;
      const other = this.posters.get(segment(x, y, i, horizontal)) ?? 0;
      if (other !== 0 && other !== ignoreUid) return false;
    }
    return true;
  }

  postersOnWall(uid: number): number[] {
    const out: number[] = [];
    for (const [k, poster] of this.posters) {
      const horizontal = k.startsWith("H:");
      const [x, y] = k.slice(2).split(",").map(Number);
      if (this.wallAt(x, y, horizontal) === uid && !out.includes(poster)) out.push(poster);
    }
    return out;
  }
}
