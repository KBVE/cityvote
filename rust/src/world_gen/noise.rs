use fastnoise_lite::{FastNoiseLite, NoiseType, FractalType};

/// Noise generator for procedural world generation
pub struct NoiseGenerator {
    continents: FastNoiseLite,
    erosion: FastNoiseLite,
    peaks: FastNoiseLite,
    temperature: FastNoiseLite,
    humidity: FastNoiseLite,
}

impl NoiseGenerator {
    /// Create a new noise generator with the given seed
    pub fn new(seed: i32) -> Self {
        // Continental-scale noise (large landmasses)
        let mut continents = FastNoiseLite::with_seed(seed);
        continents.set_noise_type(Some(NoiseType::OpenSimplex2));
        continents.set_fractal_type(Some(FractalType::FBm));
        continents.set_fractal_octaves(Some(4));
        continents.set_fractal_lacunarity(Some(2.0));
        continents.set_fractal_gain(Some(0.5));
        continents.set_frequency(Some(0.0008)); // Very low frequency for large features

        // Erosion noise (coastal detail)
        let mut erosion = FastNoiseLite::with_seed(seed + 1);
        erosion.set_noise_type(Some(NoiseType::OpenSimplex2));
        erosion.set_fractal_type(Some(FractalType::FBm));
        erosion.set_fractal_octaves(Some(3));
        erosion.set_frequency(Some(0.003));

        // Peaks and valleys (terrain variation)
        let mut peaks = FastNoiseLite::with_seed(seed + 2);
        peaks.set_noise_type(Some(NoiseType::OpenSimplex2));
        peaks.set_fractal_type(Some(FractalType::Ridged));
        peaks.set_fractal_octaves(Some(5));
        peaks.set_frequency(Some(0.01));

        // Temperature gradient (affects biomes)
        let mut temperature = FastNoiseLite::with_seed(seed + 3);
        temperature.set_noise_type(Some(NoiseType::OpenSimplex2));
        temperature.set_fractal_type(Some(FractalType::FBm));
        temperature.set_fractal_octaves(Some(2));
        temperature.set_frequency(Some(0.002));

        // Humidity (affects biomes)
        let mut humidity = FastNoiseLite::with_seed(seed + 4);
        humidity.set_noise_type(Some(NoiseType::OpenSimplex2));
        humidity.set_fractal_type(Some(FractalType::FBm));
        humidity.set_fractal_octaves(Some(3));
        humidity.set_frequency(Some(0.004));

        Self {
            continents,
            erosion,
            peaks,
            temperature,
            humidity,
        }
    }

    /// Get continental noise value at world coordinates (-1.0 to 1.0)
    pub fn get_continental(&self, x: f32, y: f32) -> f32 {
        self.continents.get_noise_2d(x, y)
    }

    /// Get erosion noise value at world coordinates (-1.0 to 1.0)
    pub fn get_erosion(&self, x: f32, y: f32) -> f32 {
        self.erosion.get_noise_2d(x, y)
    }

    /// Get peaks noise value at world coordinates (-1.0 to 1.0)
    pub fn get_peaks(&self, x: f32, y: f32) -> f32 {
        self.peaks.get_noise_2d(x, y)
    }

    /// Get temperature value at world coordinates (-1.0 to 1.0)
    pub fn get_temperature(&self, x: f32, y: f32) -> f32 {
        self.temperature.get_noise_2d(x, y)
    }

    /// Get humidity value at world coordinates (-1.0 to 1.0)
    pub fn get_humidity(&self, x: f32, y: f32) -> f32 {
        self.humidity.get_noise_2d(x, y)
    }

    /// Get combined elevation value (continental + erosion + peaks)
    /// Returns value from -1.0 to 1.0
    pub fn get_elevation(&self, x: f32, y: f32) -> f32 {
        let continental = self.get_continental(x, y);
        let erosion = self.get_erosion(x, y);
        let peaks = self.get_peaks(x, y);

        // Weighted combination: continental is primary, erosion and peaks add detail
        let base = continental * 0.7;
        let detail = erosion * 0.2 + peaks * 0.1;

        (base + detail).clamp(-1.0, 1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_noise_determinism() {
        let gen1 = NoiseGenerator::new(12345);
        let gen2 = NoiseGenerator::new(12345);

        let x = 100.5;
        let y = 200.7;

        assert_eq!(gen1.get_elevation(x, y), gen2.get_elevation(x, y));
        assert_eq!(gen1.get_temperature(x, y), gen2.get_temperature(x, y));
        assert_eq!(gen1.get_humidity(x, y), gen2.get_humidity(x, y));
    }

    #[test]
    fn test_different_seeds_produce_different_noise() {
        let gen1 = NoiseGenerator::new(12345);
        let gen2 = NoiseGenerator::new(54321);

        let x = 100.5;
        let y = 200.7;

        assert_ne!(gen1.get_elevation(x, y), gen2.get_elevation(x, y));
    }

    #[test]
    fn test_elevation_in_range() {
        let gen = NoiseGenerator::new(12345);

        for x in 0..100 {
            for y in 0..100 {
                let elevation = gen.get_elevation(x as f32, y as f32);
                assert!(elevation >= -1.0 && elevation <= 1.0);
            }
        }
    }
}
