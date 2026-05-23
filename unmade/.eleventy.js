export default function (eleventyConfig) {
  eleventyConfig.addPassthroughCopy({ "src/assets/images": "unmade/assets/images" });
  eleventyConfig.addPassthroughCopy({ "src/assets/styles": "unmade/assets/styles" });

  eleventyConfig.addFilter("displayDate", (value) => {
    const date = value instanceof Date ? value : new Date(value);
    return new Intl.DateTimeFormat("en-US", {
      month: "long",
      day: "numeric",
      year: "numeric",
    }).format(date);
  });

  return {
    dir: {
      input: "src",
      includes: "_includes",
      output: "_site",
    },
    markdownTemplateEngine: "njk",
    htmlTemplateEngine: "njk",
  };
}
