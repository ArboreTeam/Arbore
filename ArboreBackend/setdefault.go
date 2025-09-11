package main

func (p *Plant) SetDefaults() {
	if p.Type == "" {
		p.Type = "Inconnu"
	}
	if len(p.ImageURLs) == 0 {
		p.ImageURLs = []string{"https://via.placeholder.com/300x200?text=Plante"}
	}
	if p.Description == "" {
		p.Description = "Description inconnue"
	}
	if p.SoilType == "" {
		p.SoilType = "Inconnu"
	}
	if p.Exposure == "" {
		p.Exposure = "Inconnue"
	}
	if p.WateringNeeds == "" {
		p.WateringNeeds = "Inconnus"
	}
	if p.Temperature == "" {
		p.Temperature = "N.C."
	}
	if p.Floraison == "" {
		p.Floraison = "N.C."
	}
	if p.Origin == "" {
		p.Origin = "N.C."
	}
	if p.WateringReminder == "" {
		p.WateringReminder = "Non défini"
	}
	if len(p.CareTips) == 0 {
		p.CareTips = []string{"Aucun conseil disponible"}
	}
}
