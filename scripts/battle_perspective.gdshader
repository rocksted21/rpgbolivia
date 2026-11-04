shader_type canvas_item;
render_mode world_vertex_coords;

uniform vec2 focus = vec2(660.0, 450.0);
uniform vec2 screen_focus = vec2(660.0, 470.0);
uniform float ground_tilt = 0.60;
uniform float perspective = 0.001;
uniform bool upright = false;
uniform vec2 ground_anchor = vec2(0.0);
uniform float elevation = 0.0;
uniform bool tile_surface = false;
uniform vec2 tile_origin = vec2(0.0);
uniform float tile_scale = 0.5;
uniform bool scenery = false;
uniform sampler2D scenery_base : filter_nearest, repeat_disable;
// 0 = inteiro; 1 = copa ao fundo; 2 = árvores da frente.
uniform int scenery_slice = 0;
uniform float forest_split = 105.0;

varying float distance_fade;

float depth_scale(float y) {
	return 1.0 / max(0.25, 1.0 - (y - focus.y) * perspective);
}

vec2 project_ground(vec2 point, float height) {
	vec2 ground = point + vec2(0.0, height);
	return screen_focus + ((ground - focus) * vec2(1.0, ground_tilt) - vec2(0.0, height)) * depth_scale(ground.y);
}

void vertex() {
	float height = elevation;
	if (tile_surface) {
		// A lateral do hex é uma parede vertical, não mais uma parte do chão.
		vec2 local = (VERTEX - tile_origin) / tile_scale;
		float front_edge = 213.0 - abs(local.x - 93.0) * (53.0 / 93.0);
		height -= max(0.0, local.y - front_edge) * tile_scale;
	}
	float ground_y = (upright ? ground_anchor.y : VERTEX.y) + height;
	if (upright) {
		// A altura do personagem não recebe o achatamento do chão.
		VERTEX = project_ground(ground_anchor, elevation) + (VERTEX - ground_anchor) * depth_scale(ground_anchor.y + elevation);
	} else {
		VERTEX = project_ground(VERTEX, height);
	}
	distance_fade = clamp((focus.y - ground_y) / 600.0, 0.0, 1.0) * 0.10;
}

void fragment() {
	if (scenery) {
		// O kit já contém o chão sob as árvores/construções. Retira apenas os
		// pixels desse chão, que é desenhado separadamente na perspectiva.
		vec4 original = texture(TEXTURE, UV);
		vec4 base = texture(scenery_base, UV);
		float pixel_y = UV.y * float(textureSize(TEXTURE, 0).y);
		float pixel_x = UV.x * float(textureSize(TEXTURE, 0).x);
		// A grama amarelada do kit também aparece em pixels de borda que
		// diferem do piso-base. Ela fica no chão, sem acompanhar a altura da copa.
		bool grass = original.b < 0.045 && original.r > original.g * 0.71 && original.r < original.g * 0.97;
		if (scenery_slice != 0 && grass) {
			discard;
		}
		// A borda antialias do piso não faz parte das árvores altas.
		if (scenery_slice != 0 && (pixel_x < 3.0 || pixel_x > 183.0
			|| pixel_y < abs(pixel_x - 93.0) * (53.0 / 93.0) + 4.0 || pixel_y > 194.0)) {
			discard;
		}
		if (distance(original, base) < 0.015 || pixel_y > 202.0
			|| (scenery_slice == 1 && pixel_y >= forest_split)
			|| (scenery_slice == 2 && pixel_y < forest_split)) {
			discard;
		}
	}
	vec4 ink = COLOR;
	// Atmosfera discreta: as fileiras distantes perdem um pouco de contraste.
	ink.rgb = mix(ink.rgb, vec3(0.47, 0.54, 0.61), distance_fade);
	COLOR = ink;
}
