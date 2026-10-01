class_name AvatarColors
extends RefCounted
## The avatar colour choices (AvatarData.hairColor / skinColor / eyeColor):
## each a colour-matrix adjustment (contrast, brightness, saturation, hue
## in degrees) and the swatch colour shown in Edit Avatar.

const HAIR: Array[Dictionary] = [
	{"c": 1, "b": 1, "s": 1, "h": 0, "rgb": 0xD0B230},
	{"c": 1.44, "b": 1.56, "s": 1, "h": 5, "rgb": 0xF1D76E},
	{"c": 1.44, "b": 0.76, "s": 0.88, "h": -28, "rgb": 0xAA5F23},
	{"c": 1.44, "b": 0.68, "s": 0.88, "h": -44, "rgb": 0xA52519},
	{"c": 1.04, "b": 0.64, "s": 0.68, "h": -13, "rgb": 0x694828},
	{"c": 1.08, "b": 0.44, "s": 0.4, "h": -13, "rgb": 0x3E2C1B},
	{"c": 1.24, "b": 0.28, "s": -0.28, "h": 1, "rgb": 0x16263E},
	{"c": 1.08, "b": 0.36, "s": 0.12, "h": 1, "rgb": 0x000000},
]

const SKIN: Array[Dictionary] = [
	{"c": 1, "b": 1.28, "s": 0.8, "h": 1, "rgb": 0xF9ECE3},
	{"c": 1.04, "b": 1.16, "s": 1.04, "h": 15, "rgb": 0xFFECC1},
	{"c": 1, "b": 1, "s": 1, "h": 0, "rgb": 0xFAD3B2},
	{"c": 1.12, "b": 0.68, "s": 0.88, "h": 0, "rgb": 0xBB8C60},
	{"c": 1.36, "b": 0.4, "s": 0.72, "h": -7, "rgb": 0x806053},
	{"c": 1.36, "b": 0.08, "s": 0.64, "h": -7, "rgb": 0x473727},
	{"c": 1.56, "b": 0.56, "s": 1.08, "h": 60, "rgb": 0x5DBE4A},
	{"c": 1, "b": 0.8, "s": -1.48, "h": 9, "rgb": 0x5098CA},
]

const EYES: Array[Dictionary] = [
	{"c": 1, "b": 1.28, "s": 0.8, "h": 1, "rgb": 0x227ED5},
	{"c": 1, "b": 0.8, "s": -1.48, "h": 9, "rgb": 0x000000},
	{"c": 1.36, "b": 0.08, "s": 0.64, "h": -7, "rgb": 0x4F320A},
	{"c": 1.04, "b": 1.16, "s": 1.04, "h": 15, "rgb": 0x0A730A},
	{"c": 1, "b": 0.8, "s": -1.48, "h": 9, "rgb": 0x838383},
	{"c": 1.12, "b": 0.68, "s": 0.88, "h": 0, "rgb": 0x6D7C37},
	{"c": 1.56, "b": 0.56, "s": 1.08, "h": 60, "rgb": 0xBA7A4A},
	{"c": 1.36, "b": 0.4, "s": 0.72, "h": -7, "rgb": 0x9CB9C9},
	{"c": 1, "b": 0.8, "s": -1.48, "h": 9, "rgb": 0x6C4816},
]
