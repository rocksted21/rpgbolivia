// Perspectiva compartilhada pelo terreno e pelos efeitos aditivos dos herois.

uniform vec2 focus = vec2(660.0, 450.0);
uniform vec2 screen_focus = vec2(660.0, 470.0);
uniform float ground_tilt = 0.60;
uniform float perspective = 0.001;
// Afastamento da câmera: tudo encolhe em volta do centro da tela. 1 = perto.
uniform float zoom = 1.0;
uniform bool upright = false;
uniform vec2 ground_anchor = vec2(0.0);
uniform float elevation = 0.0;
uniform bool tile_surface = false;
// Chão contínuo: a textura segue o mundo e COLOR.a diz o quanto da mancha cobre o ponto.
uniform bool ground_surface = false;
uniform sampler2D ground_noise : filter_nearest, repeat_enable;
uniform float ground_edge = 0.8;
uniform float tile_scale = 0.5;
// Giro da câmera: o chão gira em volta do centro; o que fica em pé só muda de lugar.
uniform float view_angle = 0.0;
// Névoa da exploração: fim 0 desliga. A distância conta a partir do centro da câmera.
uniform float fog_start = 0.0;
uniform float fog_end = 0.0;
uniform vec3 fog_color = vec3(0.14, 0.15, 0.18);
uniform bool scenery = false;
uniform sampler2D scenery_base : filter_nearest, repeat_disable;
// 0 = inteiro; 1 = copa ao fundo; 2 = árvores da frente.
uniform int scenery_slice = 0;
uniform float forest_split = 105.0;
// Luz no chão: xy = lugar no chão já girado, z = raio, w = força. Força 0 desliga.
uniform vec4 lights[8];
uniform vec3 light_color = vec3(1.0, 0.82, 0.58);
// Mar da Cidade-Farol: água desenhada aqui mesmo, animada, em blocos de pixel.
// COLOR.r traz o quanto o ponto está perto do cais (espuma).
uniform bool sea = false;
uniform sampler2D sea_noise : filter_linear, repeat_enable;
uniform vec3 sea_deep = vec3(0.045, 0.075, 0.115);
uniform vec3 sea_mid = vec3(0.075, 0.135, 0.180);
uniform vec3 sea_light = vec3(0.125, 0.215, 0.255);
uniform vec3 sea_foam = vec3(0.52, 0.60, 0.62);
uniform vec3 sea_glint = vec3(0.78, 0.84, 0.86);

varying float distance_fade;
varying float fog;
varying float lit;

float depth_scale(float y) {
	return 1.0 / max(0.25, 1.0 - (y - focus.y) * perspective);
}

vec2 turned(vec2 point) {
	vec2 away = point - focus;
	float c = cos(view_angle);
	float s = sin(view_angle);
	return focus + vec2(away.x * c - away.y * s, away.x * s + away.y * c);
}

vec2 project_ground(vec2 point, float height) {
	vec2 ground = turned(point + vec2(0.0, height));
	return screen_focus + ((ground - focus) * vec2(1.0, ground_tilt) - vec2(0.0, height)) * depth_scale(ground.y) * zoom;
}

void vertex() {
	float height = elevation;
	if (tile_surface) {
		// A lateral do hex é uma parede vertical, não mais uma parte do chão.
		// A UV dá a posição dentro do tile mesmo com o tabuleiro em movimento.
		vec2 local = UV / TEXTURE_PIXEL_SIZE;
		float front_edge = 213.0 - abs(local.x - 93.0) * (53.0 / 93.0);
		height -= max(0.0, local.y - front_edge) * tile_scale;
	}
	vec2 ground_point = turned((upright ? ground_anchor : VERTEX) + vec2(0.0, height));
	float ground_y = ground_point.y;
	fog = fog_end > 0.0 ? smoothstep(fog_start, fog_end, length((ground_point - focus) * vec2(0.6, 1.0))) : 0.0;
	if (upright) {
		// A altura do personagem não recebe o achatamento do chão.
		VERTEX = project_ground(ground_anchor, elevation) + (VERTEX - ground_anchor) * depth_scale(turned(ground_anchor + vec2(0.0, elevation)).y) * zoom;
	} else {
		VERTEX = project_ground(VERTEX, height);
	}
	distance_fade = clamp((focus.y - ground_y) / 600.0, 0.0, 1.0) * 0.10;
	lit = 0.0;
	if (tile_surface || ground_surface || sea) {
		for (int i = 0; i < 8; i++) {
			if (lights[i].w > 0.0) {
				lit += lights[i].w * (1.0 - smoothstep(0.0, lights[i].z, distance(ground_point, lights[i].xy)));
			}
		}
	}
}

float sea_hash(vec2 v) {
	return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453);
}

vec4 sea_color(vec2 world, float shore) {
	vec2 p = floor(world / 4.0) * 4.0; // pixel 2x do jogo
	float t = TIME;
	// Fundo: duas camadas largas de ondulação, em poucos tons (sem degradê liso).
	float a = texture(sea_noise, p * vec2(1.0 / 900.0, 1.0 / 460.0) + vec2(t * 0.0035, t * 0.0012)).r;
	float b = texture(sea_noise, p * vec2(1.0 / 560.0, 1.0 / 300.0) + vec2(-t * 0.0045, t * 0.0020)).g;
	float swell = a * 0.6 + b * 0.4;
	float band = floor(clamp((swell - 0.36) / 0.28, 0.0, 0.999) * 3.0) / 2.0;
	vec3 ink = mix(sea_deep, sea_mid, band);
	// Marolas: riscos curtos na horizontal, em fileiras que correm devagar para lados
	// alternados. Cada risco acende e apaga no seu tempo; nas cristas aparecem mais.
	float lane = floor(p.y / 20.0);
	float drift = (mod(lane, 2.0) * 2.0 - 1.0) * t * 6.0;
	float x = p.x + drift + lane * 37.0;
	float slot = floor(x / 44.0);
	float seed = sea_hash(vec2(slot, lane));
	float along = fract(x / 44.0);
	float thick = step(mod(p.y, 20.0), 3.0);
	float life = 0.5 + 0.5 * sin(t * 0.9 + seed * 6.283);
	float dash = thick * step(along, 0.18 + 0.30 * seed) * step(0.54 - band * 0.22, seed) * step(0.35, life);
	ink = mix(ink, sea_light, dash);
	ink = mix(ink, sea_glint, dash * step(0.92, life) * step(0.85, seed));
	// Espuma no pé do cais: uma faixa que vai e volta com a maré.
	float fine = texture(sea_noise, p * vec2(1.0 / 160.0, 1.0 / 60.0) + vec2(t * 0.010, 0.0)).b;
	float edge = shore + (b - 0.5) * 0.45 + sin(t * 1.1 + (p.x + p.y) * 0.006) * 0.05;
	ink = mix(ink, sea_mid * 1.25, step(0.38, edge));
	ink = mix(ink, sea_light * 1.15, step(0.47, edge));
	ink = mix(ink, sea_foam, step(0.56, edge) * step(0.42, fine));
	return vec4(ink, 1.0);
}

void fragment() {
	if (sea) {
		COLOR = sea_color(UV / TEXTURE_PIXEL_SIZE, COLOR.r);
	} else if (ground_surface) {
		// O recorte vem de manchas de ruído, em blocos de pixel: a borda não segue a grade.
		vec2 world_pixel = floor(UV / TEXTURE_PIXEL_SIZE / 4.0) * 4.0;
		float patch = texture(ground_noise, world_pixel / 1024.0).r;
		if (COLOR.a + (patch - 0.5) * ground_edge < 0.5) {
			discard;
		}
		COLOR.a = 1.0;
	}
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
	// A paleta nova já tem sombras e brilhos pintados; a luz não deve estourar o piso.
	if (ground_surface) {
		float gray = dot(ink.rgb, vec3(0.299, 0.587, 0.114));
		ink.rgb = mix(vec3(gray), ink.rgb, 0.82) * 0.9;
	}
	ink.rgb *= 1.0 + min(lit, 1.0) * 0.65 * light_color;
	ink.rgb = mix(ink.rgb, fog_color, fog);
	COLOR = ink;
}
