// ==========================
// MENU MOBILE
// ==========================

const nav = document.querySelector("nav");
const navbar = document.querySelector(".navbar");

// Criando botão hamburguer
const menuBtn = document.createElement("button");

menuBtn.innerHTML = "☰";
menuBtn.classList.add("menu-btn");

navbar.appendChild(menuBtn);

menuBtn.addEventListener("click", () => {
    nav.classList.toggle("active");
});

// ==========================
// SCROLL SUAVE
// ==========================

const links = document.querySelectorAll('nav a');

links.forEach(link => {
    link.addEventListener("click", function(e) {
        e.preventDefault();

        const id = this.getAttribute("href");
        const section = document.querySelector(id);

        section.scrollIntoView({
            behavior: "smooth"
        });

        nav.classList.remove("active");
    });
});

// ==========================
// HEADER DINÂMICO
// ==========================

window.addEventListener("scroll", () => {

    const header = document.querySelector("header");

    if(window.scrollY > 50){
        header.style.background = "#7b2cbf";
        header.style.boxShadow = "0 2px 10px rgba(0,0,0,0.3)";
    } else {
        header.style.background = "#7b2cbf";
        header.style.boxShadow = "none";
    }
});

// ==========================
// ANIMAÇÃO AO ROLAR
// ==========================

const observer = new IntersectionObserver(entries => {

    entries.forEach(entry => {

        if(entry.isIntersecting){
            entry.target.classList.add("show");
        }

    });

});

const hiddenElements = document.querySelectorAll(".hidden");

hiddenElements.forEach(el => observer.observe(el));

// ==========================
// BOTÃO VOLTAR AO TOPO
// ==========================

const topBtn = document.createElement("button");

topBtn.innerHTML = "↑";
topBtn.classList.add("top-btn");

document.body.appendChild(topBtn);

window.addEventListener("scroll", () => {

    if(window.scrollY > 300){
        topBtn.classList.add("show-top");
    } else {
        topBtn.classList.remove("show-top");
    }

});

topBtn.addEventListener("click", () => {

    window.scrollTo({
        top: 0,
        behavior: "smooth"
    });

});

// ==========================
// TEMA ESCURO
// ==========================

const darkBtn = document.createElement("button");

darkBtn.innerHTML = "🌙";
darkBtn.classList.add("dark-btn");

navbar.appendChild(darkBtn);

darkBtn.addEventListener("click", () => {

    document.body.classList.toggle("dark-mode");

    if(document.body.classList.contains("dark-mode")){
        darkBtn.innerHTML = "☀️";
    } else {
        darkBtn.innerHTML = "🌙";
    }

});

// ==========================
// FORMULÁRIO FAKE
// ==========================

const form = document.querySelector("form");

if(form){

    form.addEventListener("submit", (e) => {

        e.preventDefault();

        alert("Cadastro realizado com sucesso!");

        form.reset();

    });

}